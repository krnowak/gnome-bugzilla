use strict;
use warnings;
use Bugzilla;
use WeeklyBugSummary::Hooks;

page(%{ Bugzilla->hook_args });

