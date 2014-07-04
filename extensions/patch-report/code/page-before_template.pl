use strict;
use warnings;
use Bugzilla;
use PatchReport::Hooks;

page(%{ Bugzilla->hook_args });

