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
#use Data::Dumper;
use Dpkg::Changelog::Debian;
use Debian::Debhelper::Dh_Lib qw(%dh error verbose_print restore_file_on_clean qx_cmd dirname);
use parent qw(Debian::Debhelper::Buildsystem);

sub DESCRIPTION {
        '.Net build with MSBuild.'
}

sub IS_GENERATOR_BUILD_SYSTEM {
        return 0;
}

my @STANDARD_MSBUILD_FLAGS = qw(
   -nr:false
   --nologo
   --disable-build-servers
   -p:BaseOutputPath=bin
   -p:OutputPath=bin/Release/$tfm
   -p:PackageOutputPath=bin/Release
   -p:ArtifactsPath=bin
   -p:BaseIntermediateOutputPath=obj/
);

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
        elsif ($ENV{'NETBUILD_SOLUTION'}) {
                return (-e $this->get_sourcepath($ENV{'NETBUILD_SOLUTION'})) ? 1 : 0;
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
                        push @{$this->{buildfiles}}, $buildfile;
                }
                else {
                        error("$buildfile not found");
                }
        }

        if ($ENV{'NETBUILD_TARGETS'}) {
                my @solutions;
                if ($ENV{'NETBUILD_SOLUTION'}) {
                        push @solutions, $ENV{'NETBUILD_SOLUTION'};
                }
                else {
                        @solutions = glob($this->get_sourcepath('*.sln'));
                }

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
        $this->{sdk_version} = $sdkver;

        $sdkver =~ s/\.\d+$//;
        $this->{target_framework} = 'net' . $sdkver;

        my $changelog = Dpkg::Changelog::Debian->new(range => {"count" => 1});
        $changelog->load("debian/changelog");
        my $version = @{$changelog}[0]->get_version();
        $version =~ s/-[^-]+$//;  # revision
        $version =~ s/^\d+://;    # epoch
        $version =~ s/~/-/;       # ignore tilde versions
        
        $this->{upstream_version} = $version;

        $this->{standard_flags} = [ map { s/\$tfm/$this->{target_framework}/r } @STANDARD_MSBUILD_FLAGS ];

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
        
        if (-e $this->get_sourcepath("global.json")) {
                $this->patchglobaljson();
        }

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
        my %patchfiles;

        if (-e 'debian/nh_patch') {
                verbose_print("using debian/nh_patch");
                %patchfiles = make_patchany_args('debian/nh_patch');
        }

        if (-e $patchproj) {
                verbose_print("using $patchproj");
                $patchfiles{$buildfile} = [ make_patchproj_args($patchproj) ];
        }

        # Нет определенных файлов, но аргументы для модификации есть
        if (!%patchfiles and @args) {
                my @willpatch = qx_cmd('nh_patchproj', 'clean', '--path', $buildfile, '--no-act', @args);
                foreach my $file (@willpatch) {
                        chomp($file);
                        $patchfiles{$file} = ();
                }
        }

        push @args, '--verbose' if $dh{VERBOSE};

        foreach my $file (keys %patchfiles) {
                verbose_print("patching $file");
                restore_file_on_clean($file);
                $this->doit_in_sourcedir('nh_patchproj', 'clean', '--path', $file, @args, @{ $patchfiles{$file} });
        }
}

sub patchglobaljson {
        my $this=shift;
        my $fh;
        my $modified = 0;

        open ($fh, "<", $this->get_sourcepath("global.json"))
          or error("Can't open file global.json");
        local $/;
        my $global = decode_json(<$fh>);
        close $fh;

        my $sdk_version = ${this}->{sdk_version};

        if (exists $global->{sdk}) {
                verbose_print("overriding sdk version in global.json");
                $global->{sdk}{rollForward} = "latestMajor";
                $modified = 1;
        }
        if (exists $global->{tools}) {
                if (exists $global->{tools}{dotnet}) {
                        verbose_print("overriding tools.dotnet version");
                        $global->{tools}{dotnet} = ${this}->{sdk_version};
                        $modified = 1;
                }
                if (exists $global->{tools}{runtimes}) {
                        verbose_print("dropping tools.runtimes.dotnet");
                        #$global->{tools}{runtimes}{dotnet} = [($sdk_version)];
                        delete $global->{tools}{runtimes};
                        $modified = 1;
                }
        }
        if (exists $global->{"native-tools"}) {
                verbose_print("dropping native-tools from global.json");
                delete $global->{"native-tools"};
                $modified = 1;
        }
        if ($modified) {
                restore_file_on_clean($this->get_sourcepath("global.json"));

                open ($fh, ">", $this->get_sourcepath("global.json"))
                  or error("Can't open file global.json");
                print $fh to_json($global, {pretty => 1});
                close $fh;
        }
}

sub make_patchproj_args {
        my $patchfile = shift;
        my @args;

        open my $fd, '<', $patchfile or error("Cannot open $patchfile: $!");

        while (<$fd>) {
                # Пропуск строк, начинающихся с #
                next if /^#/;
                chomp;
                my @parts = split ' ';

                push @args, '--' . shift @parts;
                push @args, @parts;
        }

        close $fd;
        return @args;
}

sub make_patchany_args {
        my $patchfile = shift;
        my %files;

        open my $fd, '<', $patchfile or error("Cannot open $patchfile: $!");

        while (<$fd>) {
                # Пропуск строк, начинающихся с #
                next if /^#/;
                chomp;
                my @parts = split ' ';

                $files{shift @parts} = \@parts;
        }

        close $fd;
        return %files;
}

sub clean {
        my $this=shift;

        if ($this->{buildfiles}) {
                foreach my $buildfile (@{$this->{buildfiles}}) {
                        $this->doit_in_sourcedir('rm', '-rf', get_intermediate_outputpath($buildfile));
                        $this->doit_in_sourcedir('rm', '-rf', get_outputpath($buildfile));
                }
        }

        # Can contains specific SDK version
        if (-e $this->get_sourcepath("global.json")) {
                rename($this->get_sourcepath("global.json"), $this->get_sourcepath("global.json.disabled"));
        }

        foreach my $command ($this->msbuild_commands('clean', @_)) {
                $this->doit_in_sourcedir(@$command);
	}

        # Restore global.json
        if (-e $this->get_sourcepath("global.json.disabled")) {
                rename($this->get_sourcepath("global.json.disabled"), $this->get_sourcepath("global.json"));
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
                my @assemblies = glob($this->get_target_outputpath('.') . '/*.dll');
                @assemblies or error("Assemblies not found");
                $this->doit_in_sourcedir('install', '-D', '-t', $libdir, @assemblies);

                my @nugets = glob($this->get_nuget_outputpath('.') . '/*.nupkg');
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
        my ($this, $buildfile, $step, @userflags) = @_;
        my @options;

        #my $dir = $this->get_sourcedir();

        print ("\t$step $buildfile\n");

        if ($buildfile) {
                push @options, $buildfile;
        }

        if ($step eq 'restore' or $step eq 'pack') {
                push @options, '-p:TargetFrameworks=';
                push @options, '-p:TargetFramework=' . $this->{target_framework};
        } else {
                push @options, '--framework', $this->{target_framework};
        }

        if ($step eq 'build' or $step eq 'test') {
                push @options, '-c', 'Release';
                push @options, '--no-restore';
        }

        if ($step eq 'pack') {
                push @options, '--no-build';
                push @options, '-p:PackageVersion=' . $this->{upstream_version};
        }

        if ($this->{targets}) {
                foreach my $target (split ' ', $this->{targets}) {
                        push @options, "-t:$target";
                }
        }

        push @options, @{$this->{standard_flags}};
        push @options, '-v', 'n' if $dh{VERBOSE};
        push @options, @userflags;

        return ['dotnet', $step, @options];
}

sub get_sln_projects {
        my ($slnfile) = shift;
        my $slnpath = dirname($slnfile);
        my %projects;

        open my $fh, '<', $slnfile or error("Cannot open $slnfile: $!");

        while (my $line = <$fh>) {
                if ($line =~ /^Project\("\{[^}]+\}"\)\s*=\s*"([^"]+)",\s*"([^"]+)"/) {
                        my ($name, $path) = ($1, $2);
                        if ($slnpath eq '.') {
                                $projects{$name} = $path =~ s/\\/\//gr;
                        }
                        else {
                                $projects{$name} = $slnpath . '/' . ($path =~ s/\\/\//gr);
                        }
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

sub get_target_outputpath {
        my $this = shift;
        my $basedir = shift;

        return get_outputpath($basedir) . '/Release/' . $this->{target_framework};
}

sub get_nuget_outputpath {
        my $this = shift;
        my $basedir = shift;

        return get_outputpath($basedir) . '/Release';
}

END {
        # Restore global.json
        if (-e "global.json.disabled") {
                rename("global.json.disabled", "global.json");
        }
}

1

