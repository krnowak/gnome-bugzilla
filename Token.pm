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
# The Initial Developer of the Original Code is Netscape Communications
# Corporation. Portions created by Netscape are
# Copyright (C) 1998 Netscape Communications Corporation. All
# Rights Reserved.
#
# Contributor(s):    Myk Melez <myk@mozilla.org>

################################################################################
# Module Initialization
################################################################################

# Make it harder for us to do dangerous things in Perl.
use strict;

# Bundle the functions in this file together into the "Token" package.
package Token;

use Bugzilla::Config;
use Bugzilla::Error;

use Date::Format;

# This module requires that its caller have said "require CGI.pl" to import
# relevant functions from that script and its companion globals.pl.

################################################################################
# Constants
################################################################################

# The maximum number of days a token will remain valid.
my $maxtokenage = 3;

################################################################################
# Functions
################################################################################

sub IssueEmailChangeToken {
    my ($userid, $old_email, $new_email) = @_;

    my $token_ts = time();
    my $issuedate = time2str("%Y-%m-%d %H:%M", $token_ts);

    # Generate a unique token and insert it into the tokens table.
    # We have to lock the tokens table before generating the token, 
    # since the database must be queried for token uniqueness.
    &::SendSQL("LOCK TABLES tokens WRITE");
    my $token = GenerateUniqueToken();
    my $quotedtoken = &::SqlQuote($token);
    my $quoted_emails = &::SqlQuote($old_email . ":" . $new_email);
    &::SendSQL("INSERT INTO tokens ( userid , issuedate , token , 
                                     tokentype , eventdata )
                VALUES             ( $userid , '$issuedate' , $quotedtoken , 
                                     'emailold' , $quoted_emails )");
    my $newtoken = GenerateUniqueToken();
    $quotedtoken = &::SqlQuote($newtoken);
    &::SendSQL("INSERT INTO tokens ( userid , issuedate , token , 
                                     tokentype , eventdata )
                VALUES             ( $userid , '$issuedate' , $quotedtoken , 
                                     'emailnew' , $quoted_emails )");
    &::SendSQL("UNLOCK TABLES");

    # Mail the user the token along with instructions for using it.

    my $template = $::template;
    my $vars = $::vars;

    $vars->{'oldemailaddress'} = $old_email . Param('emailsuffix');
    $vars->{'newemailaddress'} = $new_email . Param('emailsuffix');
    
    $vars->{'max_token_age'} = $maxtokenage;
    $vars->{'token_ts'} = $token_ts;

    $vars->{'token'} = $token;
    $vars->{'emailaddress'} = $old_email . Param('emailsuffix');

    my $message;
    $template->process("account/email/change-old.txt.tmpl", $vars, \$message)
      || ThrowTemplateError($template->error());

    open SENDMAIL, "|/usr/lib/sendmail -t -i";
    print SENDMAIL $message;
    close SENDMAIL;

    $vars->{'token'} = $newtoken;
    $vars->{'emailaddress'} = $new_email . Param('emailsuffix');

    $message = "";
    $template->process("account/email/change-new.txt.tmpl", $vars, \$message)
      || ThrowTemplateError($template->error());

    open SENDMAIL, "|/usr/lib/sendmail -t -i";
    print SENDMAIL $message;
    close SENDMAIL;

}

sub IssuePasswordToken {
    # Generates a random token, adds it to the tokens table, and sends it
    # to the user with instructions for using it to change their password.

    my ($loginname) = @_;

    # Retrieve the user's ID from the database.
    my $quotedloginname = &::SqlQuote($loginname);
    &::SendSQL("SELECT userid FROM profiles WHERE login_name = $quotedloginname");
    my ($userid) = &::FetchSQLData();

    my $token_ts = time();
    my $issuedate = time2str("%Y-%m-%d %H:%M", $token_ts);

    # Generate a unique token and insert it into the tokens table.
    # We have to lock the tokens table before generating the token, 
    # since the database must be queried for token uniqueness.
    &::SendSQL("LOCK TABLES tokens WRITE");
    my $token = GenerateUniqueToken();
    my $quotedtoken = &::SqlQuote($token);
    my $quotedipaddr = &::SqlQuote($::ENV{'REMOTE_ADDR'});
    &::SendSQL("INSERT INTO tokens ( userid , issuedate , token , tokentype , eventdata )
                VALUES      ( $userid , '$issuedate' , $quotedtoken , 'password' , $quotedipaddr )");
    &::SendSQL("UNLOCK TABLES");

    # Mail the user the token along with instructions for using it.
    
    my $template = $::template;
    my $vars = $::vars;

    $vars->{'token'} = $token;
    $vars->{'emailaddress'} = $loginname . Param('emailsuffix');

    $vars->{'max_token_age'} = $maxtokenage;
    $vars->{'token_ts'} = $token_ts;

    my $message = "";
    $template->process("account/password/forgotten-password.txt.tmpl", 
                                                               $vars, \$message)
      || ThrowTemplateError($template->error());

    open SENDMAIL, "|/usr/lib/sendmail -t -i";
    print SENDMAIL $message;
    close SENDMAIL;

}


sub CleanTokenTable {
    &::SendSQL("LOCK TABLES tokens WRITE");
    &::SendSQL("DELETE FROM tokens 
                WHERE TO_DAYS(NOW()) - TO_DAYS(issuedate) >= " . $maxtokenage);
    &::SendSQL("UNLOCK TABLES");
}


sub GenerateUniqueToken {
    # Generates a unique random token.  Uses &GenerateRandomPassword 
    # for the tokens themselves and checks uniqueness by searching for
    # the token in the "tokens" table.  Gives up if it can't come up
    # with a token after about one hundred tries.

    my $token;
    my $duplicate = 1;
    my $tries = 0;
    while ($duplicate) {

        ++$tries;
        if ($tries > 100) {
            ThrowCodeError("token_generation_error");
        }

        $token = &::GenerateRandomPassword();
        &::SendSQL("SELECT userid FROM tokens WHERE token = " . &::SqlQuote($token));
        $duplicate = &::FetchSQLData();
    }

    return $token;

}


sub Cancel {
    # Cancels a previously issued token and notifies the system administrator.
    # This should only happen when the user accidentally makes a token request
    # or when a malicious hacker makes a token request on behalf of a user.
    
    my ($token, $cancelaction) = @_;

    # Quote the token for inclusion in SQL statements.
    my $quotedtoken = &::SqlQuote($token);
    
    # Get information about the token being cancelled.
    &::SendSQL("SELECT  issuedate , tokentype , eventdata , login_name , realname
                FROM    tokens, profiles 
                WHERE   tokens.userid = profiles.userid
                AND     token = $quotedtoken");
    my ($issuedate, $tokentype, $eventdata, $loginname, $realname) = &::FetchSQLData();

    # Get the email address of the Bugzilla maintainer.
    my $maintainer = Param('maintainer');

    my $template = $::template;
    my $vars = $::vars;

    $vars->{'emailaddress'} = $loginname . Param('emailsuffix');
    $vars->{'maintainer'} = $maintainer;
    $vars->{'remoteaddress'} = $::ENV{'REMOTE_ADDR'};
    $vars->{'token'} = $token;
    $vars->{'tokentype'} = $tokentype;
    $vars->{'issuedate'} = $issuedate;
    $vars->{'eventdata'} = $eventdata;
    $vars->{'cancelaction'} = $cancelaction;

    # Notify the user via email about the cancellation.

    my $message;
    $template->process("account/cancel-token.txt.tmpl", $vars, \$message)
      || ThrowTemplateError($template->error());

    open SENDMAIL, "|/usr/lib/sendmail -t -i";
    print SENDMAIL $message;
    close SENDMAIL;

    # Delete the token from the database.
    &::SendSQL("LOCK TABLES tokens WRITE");
    &::SendSQL("DELETE FROM tokens WHERE token = $quotedtoken");
    &::SendSQL("UNLOCK TABLES");
}

sub DeletePasswordTokens {
    my ($userid, $reason) = @_;

    my $dbh = Bugzilla->dbh;
    my $sth = $dbh->prepare("SELECT token " .
                            "FROM tokens " .
                            "WHERE userid=? AND tokentype='password'");
    $sth->execute($userid);
    while (my $token = $sth->fetchrow_array) {
        Token::Cancel($token, $reason);
    }
}

sub HasEmailChangeToken {
    # Returns an email change token if the user has one. 
    
    my ($userid) = @_;
    
    &::SendSQL("SELECT token FROM tokens WHERE userid = $userid " . 
               "AND (tokentype = 'emailnew' OR tokentype = 'emailold') " . 
               "LIMIT 1");
    my ($token) = &::FetchSQLData();
    
    return $token;
}


1;
