/*
 * See http://www.perl.com/doc/manual/html/pod/perlsec.html, section
 * "Security Bugs" for an explanation of this file (and to find out where I
 * got the code in this file from).
 *
 * A simple perl script that could be used with this file to explain
 * how things work is the following:
 *
 *   #!/usr/bin/perl -w
 *   use English; # For UID & EUID
 *   print getpwuid($UID) . "\n";   # could use $< instead of $UID
 *   print getpwuid($EUID) . "\n";  # could use $> instead of $EUID
 *
 * The output of this file should have the setuid bit set and be
 * executable by all relevant users (probably group and others), while
 * the perl script only needs to be executable by the user.
 *
 * Anyway, simply compile with
 *   gcc add-version.c -o add-version
 */

#define REAL_PATH "/usr/local/www/bugzilla/bugzilla/add-version.pl"
int main(int argc, char **argv) {
  execv(REAL_PATH, argv);
}
