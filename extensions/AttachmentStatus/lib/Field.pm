# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::AttachmentStatus::Field;
use strict;
use warnings;
use base qw(Bugzilla::Field::Choice);
use Bugzilla::Extension::AttachmentStatus::Util;

use constant DB_TABLE => g_a_s();
use constant FIELD_NAME => fd_a_g_a_s();
use constant G_A_S_PKG => 'Bugzilla::Extension::AttachmentStatus::Field';

sub DB_COLUMNS {
    return ($_[0]->SUPER::DB_COLUMNS, 'description');
}

sub new_none {
    my ($type) = @_;
    my $class = ref($type) || $type || G_A_S_PKG;

    $class->new({name => 'none'});
}

1;
