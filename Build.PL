use 5.006;
use strict;
use warnings;
use Module::Build;

my $builder = Module::Build->new(
    module_name         => 'App::EUMM::Upgrade',
    license             => 'gpl3',
    dist_author         => q{Alexandr Ciornii <alexchorny@gmail.com>},
    dist_version_from   => 'lib/App/EUMM/Upgrade.pm',
    requires => {
        'File::Slurp' => 0,
        'Text::FindIndent' => 0,
        'Github::Fork::Parent' => 0,
        'ExtUtils::MakeMaker' => 6.56,
        'perl' => 5.006,
    },
    build_requires => {
        'Test::More' => 0,
    },
    script_files => [
        'eumm-upgrade.pl',
    ],
    meta_merge => {
        resources => {
            repository => 'http://github.com/chorny/EUMM-upgrade',
        },
        keywords => [
            'development','upgrade','EU::MM','Makefile.PL',
        ],
    },
    add_to_cleanup      => [ 'App-EUMM-Upgrade-*' ],
    create_makefile_pl => 'traditional',
);

$builder->create_build_script();
