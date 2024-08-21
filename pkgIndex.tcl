# Copyright Jerily LTD. All Rights Reserved.
# SPDX-FileCopyrightText: 2024 Neofytos Dimitriou (neo@jerily.cy)
# SPDX-License-Identifier: MIT.

set dir [file dirname [info script]]

package ifneeded tsession-dynamodb 1.0.0 [list source [file join $dir tcl init.tcl]]
