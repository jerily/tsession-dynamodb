# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

namespace eval ::tsession::dynamodbstore {
    variable valkey_client
    variable config {
        region "us-east-1"
    }

    proc init {config_dict} {
        package require awsdynamodb

        variable dynamodb_client
        variable config

        set config [dict merge $config $config_dict]

        set dynamodb_client [::aws::dynamodb::create $config]
    }

    proc retrieve_session {session_id} {
        variable dynamodb_client

        set table "Sessions"
        set key_dict [dict create session_id [list S $session_id]]
        #puts key_dict=$key_dict
        set session_typed [$dynamodb_client get_item $table $key_dict]

        if { $session_typed ne {} } {

            set session [::aws::dynamodb::typed_item_to_simple $session_typed]

            # check if "session" expired
            set expires [dict get ${session} expires]
            set now [clock seconds]
            if { ${now} > ${expires} } {
                destroy_session ${session_id}
                return {}
            }

            return $session
        }
        return {}
    }

    proc save_session {session_id session_dict} {
        variable dynamodb_client

        set extra_typed [list]
        if { [dict exists $session_dict extra] } {
            dict for {key value} [dict get ${session_dict} extra] {
                lappend extra_typed $key [list S ${value}]
            }
        }

        set table "Sessions"
        set item_dict [dict create \
            session_id [list S $session_id] \
            expires [list N [dict get ${session_dict} expires]] \
            extra [list M $extra_typed] \
        ]

        if {[dict exists ${session_dict} loggedin]} {
            lappend item_dict loggedin [list BOOL [dict get ${session_dict} loggedin]] \
        }

        $dynamodb_client put_item $table $item_dict
    }

    proc destroy_session {session_id} {
        variable dynamodb_client
        set table "Sessions"

        set key_dict [dict create session_id [list S $session_id]]
        $dynamodb_client delete_item $table ${key_dict}
    }

    proc touch_session {session_id session_dict} {
        set current_session_dict [retrieve_session ${session_id}]
        if { ${current_session_dict} ne {} } {
            dict set current_session_dict expires [dict get ${session_dict} expires]
            save_session ${session_id} ${current_session_dict}
        }

    }
}

