#!/usr/bonsaitools/bin/perl -w
# -*- Mode: perl; indent-tabs-mode: nil -*-
#
# The contents of this file are subject to the Mozilla Public License
# Version 1.0 (the "License"); you may not use this file except in
# compliance with the License. You may obtain a copy of the License at
# http://www.mozilla.org/MPL/
# 
# Software distributed under the License is distributed on an "AS IS"
# basis, WITHOUT WARRANTY OF ANY KIND, either express or implied. See the
# License for the specific language governing rights and limitations
# under the License.
# 
# The Original Code is the Bugzilla Bug Tracking System.
# 
# The Initial Developer of the Original Code is Netscape Communications
# Corporation. Portions created by Netscape are Copyright (C) 1998
# Netscape Communications Corporation. All Rights Reserved.
# 
# Contributor(s): Terry Weissman <terry@mozilla.org>

require "CGI.pl";

confirm_login();

if (! defined $::FORM{'pwd1'}) {
    print "Content-type: text/html\n\n";
    PutHeader("Change your password"); 
    print "
<FORM METHOD=\"post\">
<table>
<tr>
<TD ALIGN=\"right\">Please enter the new password for <b>$::COOKIE{'Bugzilla_login'}</b>:</td>
<TD><INPUT TYPE=\"password\" NAME=\"pwd1\"></td>
</tr>
<tr>
<TD ALIGN=\"right\">Re-enter your new password:</td>
<TD><INPUT TYPE=\"password\" name=\"pwd2\"></td>
</table>
<INPUT TYPE=\"submit\" VALUE=\"Submit\">\n";
    exit;
}

if ($::FORM{'pwd1'} ne $::FORM{'pwd2'}) {
    print "Content-type: text/html

<H1>Try again.</H1>
The two passwords you entered did not match.  Please click <b>Back</b> and try again.\n";
    exit;
}


my $pwd = $::FORM{'pwd1'};


if ($pwd !~ /^[a-zA-Z0-9-_]*$/ || length($pwd) < 3 || length($pwd) > 15) {
    print "Content-type: text/html

<H1>Sorry; we're picky.</H1>
Please choose a password that is between 3 and 15 characters long, and that
contains only numbers, letters, hyphens, or underlines.
<p>
Please click <b>Back</b> and try again.\n";
    exit;
}


print "Content-type: text/html\n\n";

# Generate a random salt.

sub x {
    my $sc="ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789./";
    return substr($sc, int (rand () * 100000) % (length ($sc) + 1), 1);
}
my $salt  = x() . x();

my $encrypted = crypt($pwd, $salt);

SendSQL("update profiles set password='$pwd',cryptpassword='$encrypted' where login_name=" .
        SqlQuote($::COOKIE{'Bugzilla_login'}));

SendSQL("update logincookies set cryptpassword = '$encrypted' where cookie = $::COOKIE{'Bugzilla_logincookie'}");

print "<H1>OK, done.</H1>
Your new password has been set.
<p>
<A HREF=\"query.cgi\">Back to query page.</A>\n";
