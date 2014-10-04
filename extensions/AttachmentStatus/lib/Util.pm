# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at http://mozilla.org/MPL/2.0/.
#
# This Source Code Form is "Incompatible With Secondary Licenses", as
# defined by the Mozilla Public License, v. 2.0.

package Bugzilla::Extension::AttachmentStatus::Util;
use strict;
use warnings;
use base qw(Exporter);
use Bugzilla::Constants;
use Data::Dumper;

our @EXPORT = qw(
    g_a_s
    a_g_a_s
    bz_a
    a
    as_dbg
);

# This file can be loaded by your extension via
# "use Bugzilla::Extension::AttachmentStatus::Util". You can put functions
# used by your extension in here. (Make sure you also list them in
# @EXPORT.)

sub g_a_s {
    'gnome_attachment_status'
}

sub a_g_a_s {
    'attachments.' . g_a_s();
}

sub bz_a {
    'Bugzilla::Attachment'
}

sub a {
    'attachments'
}

sub _prepare_msg {
    my $raw_msg = '';
    local $Data::Dumper::Terse = 1;
    my $dumper_used = 0;
    my $spacing = '';
    my @copy = @_;

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
            $raw_msg .= $s;
        } else {
            unless ($raw_msg =~ /\n$/) {
                $raw_msg =~ s/\s+$//;
                $raw_msg .= "\n";
            }
            $raw_msg .= Dumper($_);
            $dumper_used = 1;
        }
    }
    my $final_msg = '';
    my @splitted = split("\n", $raw_msg);
    if (@splitted > 1) {
        my $sep = '========';
        unshift(@splitted, $sep);
        push(@splitted, $sep);
    }
    foreach (@splitted) {
        next if $_ eq '';
        $final_msg .= 'GNOME attachment status: ' . $spacing . $_ . "\n";
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
