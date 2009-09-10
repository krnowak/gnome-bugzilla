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
# The Original Code is the Bugzilla Bug Tracking System.
#
# The Initial Developer of the Original Code is Everything Solved.
# Portions created by Everything Solved are Copyright (C) 2009
# Everything Solved. All Rights Reserved.
#
# Contributor(s): Bradley Baetz <bbaetz@everythingsolved.com>

use strict;

package Bugzilla::AttachmentStatus;

use base qw(Bugzilla::Field::Choice);

################################
#####   Initialization     #####
################################

use constant DB_TABLE => 'attachment_status';

# This has all the standard Bugzilla::Field::Choice columns plus "description"
sub DB_COLUMNS {
    return ($_[0]->SUPER::DB_COLUMNS, 'description');
}

sub UPDATE_COLUMNS {
    return ($_[0]->SUPER::UPDATE_COLUMNS, 'description');
}

use constant PARENT_TABLE => 'attachments';

###############################
#####     Accessors        ####
###############################

sub description { return $_[0]->{'description'}; }

# XXX - evil hack; this returns the number of bugs with
# attachments with this flag set, for compat with everything else
sub bug_count {
    my $self = shift;
    return $self->{bug_count} if defined $self->{bug_count};
    my $dbh = Bugzilla->dbh;
    my $fname = $self->field->name;
    my $count;
    $count = $dbh->selectrow_array("SELECT COUNT(DISTINCT bugs.bug_id)
                                    FROM bugs, attachments, attachment_status
                                    WHERE bugs.bug_id = attachments.bug_id
                                    AND attachments.status = attachment_status.value
                                    AND attachment_status.value = ?",
                                    undef, $self->name);
    $self->{bug_count} = $count;
    return $count;
}

############
# Mutators #
############

sub set_description { $_[0]->set('description', $_[1]);   }

#####################################
# Implement Bugzilla::Field::Choice #
#####################################

# This should be abstracted a bit more - the only thing different to the
# parent class is that the field name is attachments.status not DB_TABLE
sub field {
    my $invocant = shift;
    my $class = ref $invocant || $invocant;
    my $cache = Bugzilla->request_cache;
    $cache->{"field_$class"} ||= new Bugzilla::Field({ name => 'attachments.status' });
    return $cache->{"field_$class"};
}

sub is_static {
    my $self = shift;
    return $self->name eq 'none';
}

# Default is hardcoded to 'none', not a param
use constant is_default => 0;

###############################
#####       Methods        ####
###############################

1;

__END__

=head1 NAME

Bugzilla::AttachmentStatus - Attachment status class.

=head1 SYNOPSIS

    use Bugzilla::AttachmentStatus;

=head1 DESCRIPTION

AttachmentStatus.pm represents an attachment status object. It is an
implementation of L<Bugzilla::Object>, and thus provides all methods that
L<Bugzilla::Object> provides.

=cut
