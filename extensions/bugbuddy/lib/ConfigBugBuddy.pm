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
# The Original Code is the Bugzilla BugBuddy Plugin.
#
# The Initial Developer of the Original Code is Canonical Ltd.
# Portions created by Canonical Ltd. are Copyright (C) 2009
# Canonical Ltd. All Rights Reserved.
#
# Contributor(s): Bradley Baetz <bbaetz@acm.org>

package extensions::bugbuddy::lib::ConfigBugBuddy;

use strict;

use Bugzilla::Config::Common;

$extensions::bugbuddy::lib::ConfigBugBuddy::sortkey = '99';

sub check_version {
    my $version = shift;

    # This may not capture everything, but it handles gnome version numbers
    if ($version !~ /^\d+[a-z]*([-.]\d+[a-z]*)*$/i) {
        return "Must be a version number";
    }

    return "";
}

sub get_param_list {
    my ($class) = @_;

    my @param_list = (
    {
        name => 'bugbuddy_min_version',
        type => 't',
        default => '2.20.0',
        checker => \&check_version,
    },
    );
    return @param_list;
}

1;
