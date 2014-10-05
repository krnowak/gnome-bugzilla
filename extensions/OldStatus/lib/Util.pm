# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::OldStatus::Util;
use strict;
use warnings;
use base qw(Exporter);
use Bugzilla::Constants;
use Data::Dumper;

our @EXPORT = qw(
    bz_a
    st
    a_s
    a
    a_st
    elegant_dump
    as_dbg
);

# This file can be loaded by your extension via
# "use Bugzilla::Extension::AttachmentStatus::Util". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)

sub bz_a {
    'Bugzilla::Attachment'
}

sub st {
    'status';
}

sub a_s {
    'attachment_' . st ();
}

sub a {
    'attachments'
}

sub a_st {
    a() . '.' . st();
}

sub elegant_dump
{
    my ($data, $clean) = @_;

    $clean = (defined($clean) and $clean);

    local $Data::Dumper::Purity = $clean;
    local $Data::Dumper::Deepcopy = $clean;
    local $Data::Dumper::Terse = not $clean;
    local $Data::Dumper::Sortkeys = 1;

    return Dumper($data);
}

sub _prepare_msg {
    my $dumper_used = 0;
    my $spacing = '';
    my @copy = @_;
    my @raw_msg_parts = ();

    if ((@copy > 0) && defined ($copy[0]) && (ref($copy[0]) eq '') && ($copy[0] =~ /^(\s+)/)) {
        $spacing = $1;
        $copy[0] =~ s/^\s+//;
    }

    foreach (@copy) {
        $_ = '<UNDEF>' unless defined;

        if (ref eq '') {
            my $s = $_;
            if ($dumper_used) {
                $dumper_used = 0;
                $s =~ s/^,?\s*//;
            }
            push(@raw_msg_parts, $s);
        } else {
            unless ($raw_msg_parts[-1] =~ /\n$/) {
                $raw_msg_parts[-1] =~ s/\s+$//;
                push (@raw_msg_parts, "\n");
            }
            push (@raw_msg_parts, elegant_dump($_));
            $dumper_used = 1;
        }
    }
    my $final_msg = '';
    my @splitted = split("\n", join('', @raw_msg_parts));
    if (@splitted > 1) {
        my $sep = '========';
        unshift(@splitted, $sep);
        push(@splitted, $sep);
    }
    foreach (@splitted) {
        next if $_ eq '';
        $final_msg .= 'Old attachment status: ' . $spacing . $_ . "\n";
    }

    return $final_msg;
}

sub as_dbg {
    my $datadir = bz_locations()->{'datadir'};

    if (-w "$datadir/errorlog") {
        my $mesg = _prepare_msg(@_);

        open(ERRORLOGFID, ">>$datadir/errorlog");
        print ERRORLOGFID $mesg;
        close ERRORLOGFID;
    }
}

1;
