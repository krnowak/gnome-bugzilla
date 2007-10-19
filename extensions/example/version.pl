# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public
# License Version 1.1 (the "License"); you may not use this file
# except in compliance with the License. You may obtain a copy of
# the License at http://www.mozilla.org/MPL/
#
# Software distributed under the License is distributed on an "AS
# IS" basis, WITHOUT WARRANTY OF ANY KIND, either express or
# implied. See the License for the specific language governing
# rights and limitations under the License.
#
# The Original Code is the Bugzilla Example WebService Plugin
#
# The Initial Developer of the Original Code is Everything Solved, Inc.
# Portions created by Everything Solved, Inc. are Copyright (C) 2007
# Everything Solved, Inc. All Rights Reserved.
#
# Contributor(s): Max Kanat-Alexander <mkanat@bugzilla.org>

# This script does some code to return a version number. However,
# most plugins will probably just want to return a raw string.
# To do that, the only contents of the file should be the string
# on a single line, like:
#
# '1.2.3';

use strict;
no warnings qw(void); # Avoid "useless use of a constant in void context"
use Bugzilla::Constants;
BUGZILLA_VERSION;
