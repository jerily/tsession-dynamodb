# Provision infra/infra.yml in LocalStack before running this example.
package require tsession-dynamodb 2.0.0
set client [::aws::dynamodb::create {
    region us-east-1 endpoint http://localhost:4566
    aws_access_key_id test aws_secret_access_key test
}]
try {
    set store [::tsession::dynamodb::create -client $client -table SessionsV2 -tenant example]
    # In an application use an unpredictable token, storing its MAC as the ID.
    set id example-[pid]-[clock microseconds]
    ::tsession::dynamodb::insert $store $id [dict create expires [expr {[clock seconds]+3600}]] user-1
    ::tsession::dynamodb::update $store $id {preference dark}
    puts [::tsession::dynamodb::get $store $id]
    ::tsession::dynamodb::revoke $store user-1
} finally {
    $client destroy
}
