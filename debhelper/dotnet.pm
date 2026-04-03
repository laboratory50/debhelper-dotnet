# A debhelper build system class for handling .Net (arcade) based projects.
# It prefers out of source tree building.
#
# Copyright: © 2022 Laboratory 50
# License: GPL-3+

package Debian::Debhelper::Buildsystem::dotnet;

use strict;
use warnings;
use JSON;
use File::Basename;
use File::Find::Rule qw/ find rule /;
use Data::Dumper;
use Debian::Debhelper::Dh_Lib qw(%dh error verbose_print restore_file_on_clean);
use parent qw(Debian::Debhelper::Buildsystem);

sub DESCRIPTION {
        ".Net build with MSBuild"
}

sub IS_GENERATOR_BUILD_SYSTEM {
        return 0;
}

sub get_sdk_version {
        my $base;
        my @sdk;
        if (-d "/usr/lib/mono/sdk") {
                $base = "/usr/lib/dotnet/sdk";
        }
        elsif (-d "/usr/lib/dotnet/sdk") {
                $base = "/usr/lib/dotnet/sdk";
        }
        elsif (-d "/usr/share/dotnet/sdk") {
                $base = "/usr/share/dotnet/sdk";
        }
        else {
                error(".Net SDK not found");
        }

        @sdk = find(
          directory =>
            maxdepth => 1,
            name => qr/\d+\.\d+\.\d+/,
        )->in($base);

        error(".Net SDK not found") if (!@sdk);

        verbose_print("found .Net SDK @sdk");
        return basename(shift(@sdk));
}

sub check_auto_buildable {
        my $this=shift;
        my ($step)=@_;

        if ($ENV{'NETBUILD_BUILDFILE'}) {
                return (-e $this->get_sourcepath($ENV{'NETBUILD_BUILDFILE'})) ? 1 : 0;
        }
        else {
                return (-e $this->get_sourcepath('*.sln') || -e $this->get_sourcepath('*.cproj')) ? 1 : 0;
        }
}

sub new {
        my $class=shift;
        my $this=$class->SUPER::new(@_);
        my %projects;
        my $tfm;

        $this->prefer_out_of_source_building(@_);

        if ($ENV{'NETBUILD_BUILDFILE'}) {
                my $buildfile = $ENV{'NETBUILD_BUILDFILE'};
                if (-e $this->get_sourcepath($buildfile)) {
                        $this->{buildfiles} = ($buildfile);
                }
                else {
                        error("$buildfile not found");
                }
        }

        if ($ENV{'NETBUILD_TARGETS'}) {
                my @solutions=glob($this->get_sourcepath('*.sln'));

                if (@solutions > 1) {
                        error("Multiple .sln files");
                }
                elsif (@solutions > 0) {
                        %projects = get_sln_projects($solutions[0]);
                        #print "Projects:\n" . Dumper(\%projects);
                        my @targets = split /\s+/, $ENV{'NETBUILD_TARGETS'} =~ s/,/ /r;

                        foreach my $target (@targets) {
                                if (exists $projects{$target}) {
                                        push @{$this->{buildfiles}}, $projects{$target};
                                }
                        }
                }
        }

        $self->{target_framework} = "net" . $self->get_sdk_version();

#        my @projects=glob($this->get_sourcepath('*.cproj'));
#
#        if (@projects > 1) {
#                error("Multiple .cproj files");
#        }
#        elsif (@projects > 0) {
#        }

        return $this;
}

sub configure {
        my $this=shift;
        foreach my $command ($this->msbuild_commands('restore', @_)) {
                $this->doit_in_sourcedir(@$command);
	}
}

sub clean {
        my $this=shift;
        foreach my $command ($this->msbuild_commands('clean', @_)) {
                $this->doit_in_sourcedir(@$command);
	}

        if ($this->{buildfiles}) {
                foreach my $buildfile (@{$this->{buildfiles}}) {
                        $this->doit_in_sourcedir('rm', '-rf', get_intermediate_outputpath($buildfile));
                        $this->doit_in_sourcedir('rm', '-rf', get_outputpath($buildfile));
                }
        }
}

sub build {
        my $this=shift;
        foreach my $command ($this->msbuild_commands('build', @_)) {
                $this->doit_in_sourcedir(@$command);
	}
        foreach my $command ($this->msbuild_commands('pack', @_)) {
                $this->doit_in_sourcedir(@$command);
	}
}

sub test {
        my $this=shift;
        foreach my $command ($this->msbuild_commands('test', @_)) {
                $this->doit_in_sourcedir(@$command);
	}
}

sub msbuild_commands {
        my $this = shift;
        my @result;

        if ($this->{buildfiles}) {
                foreach my $buildfile (@{$this->{buildfiles}}) {
                        push @result, $this->msbuild_command($buildfile, @_);
                }
        }
        else {
                push @result, $this->msbuild_command(undef, @_);
        }

        return @result;
}

sub msbuild_command {
        my $this = shift;
        my $buildfile = shift;
        my $step = shift;
        my @options = @_;

        #my $dir = $this->get_sourcedir();

        print ("\t$step $buildfile\n");

        push @options, '-p:TargetFrameworks='
        push @options, '-p:TargetFramework=' . $this->{target_framework}

        if ($buildfile) {
                push @options, $buildfile;
        }

        if ($step eq 'build' or $step eq 'test') {
                push @options, '-c', 'Release';
        }

        if ($this->{targets}) {
                foreach my $target (split ' ', $this->{targets}) {
                        push @options, "-t:$target";
                }
        }

        return ['dotnet', $step, @options];
}

sub get_sln_projects {
        my ($slnfile) = shift;
        my %projects;

        open my $fh, '<', $slnfile or error("Cannot open $slnfile: $!");

        while (my $line = <$fh>) {
                if ($line =~ /^Project\("\{[^}]+\}"\)\s*=\s*"([^"]+)",\s*"([^"]+)"/) {
                        my ($name, $path) = ($1, $2);
                        $projects{$name} = $path =~ s/\\/\//gr;
                }
        }

        close $fh;
        return %projects;
}

sub get_intermediate_outputpath {
        return dirname(shift) . '/obj';
}

sub get_outputpath {
        return dirname(shift) . '/bin';
}

1

