#!/usr/bin/env perl

use strict;
use warnings;
use 5.010;

use Cwd qw(getcwd abs_path);
use Archive::Zip qw(:ERROR_CODES);
use File::Path qw(rmtree);
use File::Copy::Recursive qw(fcopy dircopy);

my $jar_bin;
my $mod;
my $verbose = 0;
my $backup  = 0;
my $restore = 0;
my $home    = $ENV{HOME}
    or die "Could not get home from \$ENV\n";
my $app_dir = "${home}/.minecraft-app"; 
my $last    = $ARGV[ scalar(@ARGV) -1 ];

while(my $arg = shift @ARGV) {
    for ($arg) {
        if (/^backup$/)     { $backup = 1; }
        elsif (/^restore$/) { $restore = 1; }
        elsif (/^install$/) { $mod = 1; }
        elsif (/^-v$|^--verbose$/) { $verbose = 1; }
        elsif (/^-j$|^--jar$/) { $jar_bin = shift @ARGV; }
    }
}

$mod = $last
    if $mod;

print $_ . "\n" for ( @ARGV );

sub _create_config {
    open my $cfg, '>', "${app_dir}/config.yml" or
        return (0, "Could not write to ${app_dir}/config.yml");
    print $cfg "Minecraft:\n";
    print $cfg "  bin: ${app_dir}/minecraft.jar\n";
    close $cfg;

    return 1;
}

INITIALIZATORING: {
    say "[info] Initialising Minecraft Manager..."
        if $verbose;

    if (not -e $app_dir) {
        print "[info] Could not locate app dir, creating... ";
        if (my $mkdir = mkdir($app_dir)) {
            say "Done!";
        }
        else {
            print "Failed, because: $!\n";
            exit(1);
        }
    }

    # is jar installed?
    print "[info] Searching for the jar binary... "
        if $verbose;

    if ($jar_bin) {
        if (not -e $jar_bin) {
            say "Failed" if $verbose;
            die "[error] Could not find 'jar' binary in $jar_bin\n";
            exit(1);
        }
        else {
            say "Found in ${jar_bin}" if $verbose;
        }
    }
    else {
        if (my $path_env = $ENV{PATH}) {
            my @paths = split ':', $path_env;
            for my $path (@paths) {
                $jar_bin = "${path}/jar"
                    if -e "${path}/jar";
            }

            if ($jar_bin) {
                say "Found in ${jar_bin}" if $verbose;
            }
            else {
                say "Failed" if $verbose;
                die "[error] Could not find the 'jar' binary in your paths or config\n";
                exit(1);
            }
        }
    }
}

if ($backup and $restore) {
    die "[stupidity] Why are you trying to backup and restore at the same time?\n";
    exit(1);
}

sub _run_backup {
    if (my $num_files_and_dirs = dircopy("${home}/.minecraft", "${app_dir}/minecraft")) {
        say "[info] Successfully backed up ${num_files_and_dirs} files and directories";
        exit(0);
    }
    else {
        die "[error] Backup failed\n";
        exit(1);
    }
}

sub _run_restore {
    if (my $num_files_and_dirs = dircopy("${app_dir}/minecraft", "${home}/.minecraft")) {
        say "[info] Successfully restored ${num_files_and_dirs} files and directories";
        exit(0);
    }
    else {
        die "[error] Restore failed\n";
        exit(1);
    }
}

sub _run_install {
    if ($mod) {
        if (-e $mod) {
            my $err;
            my $zip = Archive::Zip->new();
            say "[info] Installing ${mod}... ";
            print "[info] Verifying Zip... ";
            unless ($zip->read($mod) == AZ_OK) {
                die "Failed\n";
                exit(1);
            }

            rmtree "${app_dir}/jar"
                if -d "${app_dir}/jar";
            
            my $mod_path = ($mod =~ /\//) ? 
                abs_path($mod) : getcwd();
            mkdir "${app_dir}/jar";
            chdir "${app_dir}/jar";
            $err = `$jar_bin -xf ${home}/.minecraft/bin/minecraft.jar`;

            if ($err) {
                die "[error} Failed extracting minecraft jar file\n";
                chdir("${app_dir}");
                rmtree "${app_dir}/jar";
                exit(1);
            }
            
            if (-f "${app_dir}/jar/META-INF") { rmtree "{$app_dir}/jar/META-INF"; }
            say "OK";

            say "[info] Copying archive and installing...";
            fcopy("${mod_path}/${mod}", "${app_dir}/jar/${mod}");
            $zip = Archive::Zip->new("${app_dir}/jar/${mod}");
            # FIXME: Loop over once to see if the format is OK?
            foreach my $member ($zip->members) {
                $member->extractToFileNamed(
                    "${app_dir}/jar/" . $member->fileName);
            }
            
            unlink "${app_dir}/jar/${mod}";
            $err = `$jar_bin -uf ${home}/.minecraft/bin/minecraft.jar ./`;

            if ($err) {
                die "[error] There was a problem making minecraft.jar -- Please restore\n";
                exit(1);
            }

            chdir("${app_dir}");
            rmtree("${app_dir}/jar");
            say "[info] Finished installing mod";
            exit(0);
        }
        else {
            die "[error] Can't find mod ${mod}\n";
            exit(1);
        }
    }
    else {
        die "[error] No mod was chosen to be installed\n";
        exit(1);
    }    
}

_run_backup() if $backup;
_run_restore() if $restore;
_run_install() if $mod;

