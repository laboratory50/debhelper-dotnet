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
use Dpkg::Changelog::Debian;
use Debian::Debhelper::Dh_Lib qw(%dh error verbose_print restore_file_on_clean);
use parent qw(Debian::Debhelper::Buildsystem);

our $BIN_DIR = 'bin';
our $OBJ_DIR = 'obj';
our $BUILD_CONFIG = 'Release';

sub DESCRIPTION {
        '.Net build with MSBuild.'
}

sub IS_GENERATOR_BUILD_SYSTEM {
        return 0;
}

sub lib_install_dir {
        return '/usr/lib/sharedstore';
}

sub nuget_install_dir {
        return '/usr/lib/nuget';
}

sub get_sdk_version {
        my $base;
        my @sdk;
        if (-d "/usr/lib/mono/sdk") {
                $base = "/usr/lib/mono/sdk";
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
                return (-e $this->get_sourcepath('*.sln') || -e $this->get_sourcepath('*.csproj')) ? 1 : 0;
        }
}

sub new {
        my $class=shift;
        my $this=$class->SUPER::new(@_);
        my %projects;
        my $sdkver;

        $this->prefer_out_of_source_building(@_);

        if ($ENV{'NETBUILD_BUILDFILE'}) {
                my $buildfile = $ENV{'NETBUILD_BUILDFILE'};
                if (-e $this->get_sourcepath($buildfile)) {
                        $this->{buildfiles} = [$buildfile];
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

        $sdkver = $this->get_sdk_version();
        $sdkver =~ s/\.\d+$//;

        $this->{target_framework} = 'net' . $sdkver;

        my $changelog = Dpkg::Changelog::Debian->new(range => {"count" => 1});
        $changelog->load("debian/changelog");
        my $version = @{$changelog}[0]->get_version();
        $version =~ s/-[^-]+$//;  # revision
        $version =~ s/^\d+://;    # epoch
        $version =~ s/~/-/;       # ignore tilde versions
        
        $this->{upstream_version} = $version;

#        my @projects=glob($this->get_sourcepath('*.csproj'));
#
#        if (@projects > 1) {
#                error("Multiple .csproj files");
#        }
#        elsif (@projects > 0) {
#        }

        return $this;
}

sub configure {
        my $this=shift;

        if ($this->{buildfiles}) {
                foreach my $buildfile (@{$this->{buildfiles}}) {
                        $this->patchproj($buildfile, @_);
                }
        }

        $ENV{NUGET_OFFLINE} = 1;
        foreach my $command ($this->msbuild_commands('restore', @_)) {
                $this->doit_in_sourcedir(@$command);
	}
}

sub patchproj {
        my $this=shift;
        my $buildfile=shift;
        my @args = @_;
        my $patchproj = 'debian/' . lc(basename($buildfile, '.csproj'));

        if (-e $patchproj) {
                verbose_print("using $patchproj");
                push @args, make_patchproj_args($patchproj);
        }
        
        if (@args) {
                verbose_print("patching $buildfile");
                #restore_file_on_clean($buildfile);
                $this->doit_in_sourcedir('nh_patchproj', 'clean', '--path', $buildfile, '--quiet', '--no-backup', @args);
        }
}

sub make_patchproj_args {
        my @args;
        my $patchfile = shift;

        if (-e $patchfile) {
                open my $fd, '<', $patchfile or error("Cannot open $patchfile: $!");

                while (<$fd>) {
                        # Пропуск строк, начинающихся с #
                        next if /^#/;
                        chomp($_);
                        my @parts = split ' ';

                        push @args, '--' . shift @parts;
                        push @args, @parts;
                }
                close $fd;
        }
        return @args;
}

sub clean {
        my $this=shift;

        foreach my $command ($this->msbuild_commands('clean', @_)) {
                $this->doit_in_sourcedir(@$command);
	}

        if ($this->{buildfiles}) {
                verbose_print("Manual cleanup of build directories...");
                foreach my $buildfile (@{$this->{buildfiles}}) {
                        my $base = dirname($buildfile);
                        my $obj_path = "${base}/${OBJ_DIR}";
                        my $bin_path = "${base}/${BIN_DIR}";
                        
                        $this->doit_in_sourcedir('rm', '-rf', $obj_path) if -e $obj_path;
                        $this->doit_in_sourcedir('rm', '-rf', $bin_path) if -e $bin_path;
                }
        } else {
                my $sourcedir = $this->get_sourcedir();
                my $obj_path = "${sourcedir}/${OBJ_DIR}";
                my $bin_path = "${sourcedir}/${BIN_DIR}";
                
                $this->doit_in_sourcedir('rm', '-rf', $obj_path) if -e $obj_path;
                $this->doit_in_sourcedir('rm', '-rf', $bin_path) if -e $bin_path;
        }

}

sub build {
        my $this=shift;

        $ENV{NUGET_OFFLINE} = 1;
        foreach my $command ($this->msbuild_commands('build', @_)) {
                $this->doit_in_sourcedir(@$command);
	}
        foreach my $command ($this->msbuild_commands('pack', @_)) {
                $this->doit_in_sourcedir(@$command);
	}
}

sub test {
        my $this = shift;
        foreach my $command ($this->msbuild_commands('test', @_)) {
                $this->doit_in_sourcedir(@$command);
	}
}

sub install {
        my $this = shift;
        my $destdir = shift;
        my $libdir = $destdir . lib_install_dir();
        my $nugetdir = $destdir . nuget_install_dir();
        my $sourcedir = $this->get_sourcedir();

        if ($this->{buildfiles}) {
                foreach my $buildfile (@{$this->{buildfiles}}) {
                        my @assemblies = glob($this->get_target_outputpath($buildfile) . '/*.dll');
                        @assemblies or error("Assemblies not found");
                        $this->doit_in_sourcedir('install', '-D', '-t', $libdir, @assemblies);

                        my @nugets = glob($this->get_nuget_outputpath($buildfile) . '/*.nupkg');
                        @nugets or error("NuGet packages not found");
                        $this->doit_in_sourcedir('install', '-D', '-t', $nugetdir, @nugets);
                }
        } else {
                my @assemblies = glob($sourcedir . '/' . $this->get_target_outputpath('.') . '/*.dll');
                @assemblies or error("Assemblies not found");
                $this->doit_in_sourcedir('install', '-D', '-t', $libdir, @assemblies);

                my @nugets = glob($sourcedir . '/' . $this->get_nuget_outputpath('.') . '/*.nupkg');
                @nugets or error("NuGet packages not found");
                $this->doit_in_sourcedir('install', '-D', '-t', $nugetdir, @nugets);
        }
}

sub msbuild_commands {
        my $this = shift;
        my @result;

        if ($this->{buildfiles}) {
                foreach my $buildfile (@{$this->{buildfiles}}) {
                        push @result, $this->msbuild_command($buildfile, @_);
                }
        } else {
                push @result, $this->msbuild_command(undef, @_);
        }

        return @result;
}

sub msbuild_command {
        my $this = shift;
        my $buildfile = shift;
        my $step = shift;
        my @options = @_;

        print ("\t$step $buildfile\n");

        if ($buildfile) {
                push @options, $buildfile;
        }

        push @options, '--nologo';
        push @options, '--disable-build-servers';

        if ($step eq 'restore' or $step eq 'pack') {
                push @options, '-p:TargetFrameworks=' . $this->{target_framework};
        } else {
                push @options, '--framework', $this->{target_framework};
        }

        if ($step eq 'build' or $step eq 'test') {
                push @options, '-c', 'Release';
                push @options, '--no-restore';
                push @options, '-p:LangVersion=12.0';
                push @options, '-p:TreatWarningsAsErrors=false';
        }

        if ($step eq 'pack') {
                push @options, '--no-build';
                push @options, '-p:PackageVersion=' . $this->{upstream_version};
        }
        
        if ($buildfile && ($step eq 'restore' || $step eq 'build' || $step eq 'pack')) {
              my $tfm = $this->{target_framework};
              push @options, "-p:BaseOutputPath=${BIN_DIR}/";
              push @options, "-p:OutputPath=${BIN_DIR}/${BUILD_CONFIG}/${tfm}/";
              push @options, "-p:PackageOutputPath=${BIN_DIR}/${BUILD_CONFIG}/";
              push @options, "-p:ArtifactsPath=${BIN_DIR}/";
              push @options, "-p:BaseIntermediateOutputPath=${OBJ_DIR}/";
        }

        if ($this->{targets}) {
                foreach my $target (split ' ', $this->{targets}) {
                        push @options, "-t:$target";
                }
        }

        push @options, '-nr:false';
        push @options, '-v', 'n' if not $dh{QUIET};

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
        return dirname(shift) . "/${OBJ_DIR}";
}

sub get_outputpath {
        return dirname(shift) . "/${BIN_DIR}";
}

sub get_target_outputpath {
        my $this = shift;
        my $basedir = shift;

        return get_outputpath($basedir) . "/${BUILD_CONFIG}/" . $this->{target_framework};
}

sub get_nuget_outputpath {
        my $this = shift;
        my $basedir = shift;

        return get_outputpath($basedir) . "/${BUILD_CONFIG}";
}

1

