# Copyright Jerily LTD. All Rights Reserved.
# SPDX-License-Identifier: MIT
package require Tcl 8.6.14-9 9.0-10
package require tsession 2.0.0
package require awsdynamodb 1.0.18
source [file join [file dirname [info script]] dynamodbstore.tcl]
package provide tsession-dynamodb 2.0.0
