# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

package provide tsession-dynamodb 1.0.0

package require tsession

set dir [file dirname [info script]]
source [file join ${dir} dynamodbstore.tcl]
