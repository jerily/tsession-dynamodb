# Copyright Jerily LTD. All Rights Reserved.
# SPDX-License-Identifier: MIT
# A store is a value; the host owns the AWS client and provisions the table.
namespace eval ::tsession::dynamodb {}

proc ::tsession::dynamodb::create {args} {
    set store {client {} table {} tenant {}}
    if {[llength $args] % 2} {error "expected option/value pairs"}
    foreach {key value} $args {
        if {$key ni {-client -table -tenant}} {error "unknown store option: $key"}
        dict set store [string range $key 1 end] $value
    }
    foreach key {client table tenant} {
        if {[dict get $store $key] eq {}} {error "-$key is required"}
    }
    set client [namespace which -command [dict get $store client]]
    if {$client eq {}} {error "-client must name an existing DynamoDB client command"}
    dict set store client $client
    if {![regexp {^[A-Za-z0-9_.-]{3,255}$} [dict get $store table]]} {error "invalid DynamoDB table name"}
    key_string [dict get $store tenant] 1024 tenant
    return $store
}

# Hex keys avoid delimiter collisions and preserve arbitrary Tcl identifiers.
proc ::tsession::dynamodb::key_string {value maxbytes name} {
    set bytes [encoding convertto utf-8 $value]
    if {$value eq {} || [string length $bytes] > $maxbytes} {
        error "$name must contain 1-$maxbytes UTF-8 bytes"
    }
    return [binary encode hex $bytes]
}

proc ::tsession::dynamodb::key {store id} {
    dict create tenant [list S [key_string [dict get $store tenant] 1024 tenant]] \
        id [list S [key_string $id 512 {session id}]]
}

proc ::tsession::dynamodb::validate_data {data} {
    if {![dict exists $data expires] || ![string is wideinteger -strict [dict get $data expires]]} {
        error "session data requires an integer expires timestamp"
    }
}

proc ::tsession::dynamodb::encode {value} {
    binary encode base64 -maxlen 0 [encoding convertto utf-8 $value]
}

proc ::tsession::dynamodb::decode {value} {
    encoding convertfrom utf-8 [binary decode base64 -strict $value]
}

proc ::tsession::dynamodb::row {store id} {
    set item [[dict get $store client] get_item [dict get $store table] [key $store $id] true]
    if {$item eq {}} {return {}}
    set row [::aws::dynamodb::typed_item_to_simple $item]
    if {[dict get $row expires] <= [clock seconds]} {return {}}
    return $row
}

proc ::tsession::dynamodb::get {store id} {
    set row [row $store $id]
    if {$row eq {}} {return {}}
    return [dict replace [decode [dict get $row data]] id $id expires [dict get $row expires]]
}

proc ::tsession::dynamodb::item {store id data subject revision} {
    validate_data $data
    dict merge [key $store $id] [dict create subject [list S [encode $subject]] \
        expires [list N [expr {wide([dict get $data expires])}]] \
        data [list S [encode [dict replace $data id $id]]] revision [list N $revision]]
}

proc ::tsession::dynamodb::insert {store id data {subject {}}} {
    set item [item $store $id $data $subject 0]
    [dict get $store client] put_item [dict get $store table] $item \
        {condition_expression {attribute_not_exists(#id)} expression_attribute_names {#id id}}
    return
}

# Only conditional conflicts become a zero result; transport/service errors propagate.
proc ::tsession::dynamodb::conditional {store method value options} {
    try {
        [dict get $store client] $method [dict get $store table] $value $options
    } trap {AWS DynamoDB ConditionalCheckFailedException} {} {
        return 0
    }
    return 1
}

proc ::tsession::dynamodb::update {store id changes} {
    if {[dict exists $changes id]} {error "session id cannot be updated"}
    set row [row $store $id]
    if {$row eq {}} {return 0}
    set data [dict merge [decode [dict get $row data]] $changes]
    set item [item $store $id $data [decode [dict get $row subject]] [expr {[dict get $row revision]+1}]]
    set options [dict create condition_expression {#revision = :revision AND #expires > :now} \
        expression_attribute_names {#revision revision #expires expires} \
        expression_attribute_values [dict create :revision [list N [dict get $row revision]] :now [list N [clock seconds]]]]
    return [conditional $store put_item $item $options]
}

proc ::tsession::dynamodb::delete {store id} {
    conditional $store delete_item [key $store $id] \
        {condition_expression {attribute_exists(#id)} expression_attribute_names {#id id}}
}

# Query the base table with strong consistency, following every page in the SDK.
# This avoids relying on eventually consistent secondary indexes for revocation.
proc ::tsession::dynamodb::rows {store} {
    [dict get $store client] query_items [dict get $store table] \
        [dict create tenant [list S [key_string [dict get $store tenant] 1024 tenant]]] {} {} {} {} true
}

proc ::tsession::dynamodb::revoke {store subject} {
    if {$subject eq {}} {error "subject must not be empty"}
    set subject [encode $subject]
    set options [dict create condition_expression {#subject = :subject} \
        expression_attribute_names {#subject subject} expression_attribute_values [dict create :subject [list S $subject]]]
    set count 0
    foreach item [rows $store] {
        if {[lindex [dict get $item subject] 1] ne $subject} {continue}
        incr count [conditional $store delete_item [dict create tenant [dict get $item tenant] id [dict get $item id]] $options]
    }
    return $count
}

proc ::tsession::dynamodb::prune {store} {
    set now [clock seconds]
    set options [dict create condition_expression {#expires <= :now} \
        expression_attribute_names {#expires expires} expression_attribute_values [dict create :now [list N $now]]]
    set count 0
    foreach item [rows $store] {
        if {[lindex [dict get $item expires] 1] > $now} {continue}
        incr count [conditional $store delete_item [dict create tenant [dict get $item tenant] id [dict get $item id]] $options]
    }
    return $count
}
