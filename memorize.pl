#!/usr/bin/perl

=head1 NAME

memorize

=head1 DESCRIPTION

A program to quiz the user on ... anything, using spaced repetition.

Keith Nazworth wrote this while working at Grant Street Group.  If you have
questions or need help using this script, email me or other developers at GSG
at developers@grantstreet.com or to my personal email, keith.nazworth@gmail.com

=head1 SYNOPSIS

    cat > facts.mem <<EOF
    MEM -- Facts I Want to Remember
    What is PI?{tab}3.1415
    What is Sue's birthday{tab}Jan 30th
    [etc]
    EOF

    $ memorize.pl facts.mem
    # enjoy memorizing your facts

=cut

use warnings;
use strict;
use Term::ReadKey;
use Data::Dumper;

my ($filename) = @ARGV;

my ($title, $set) = load($filename);
print "$title\n";

$SIG{INT} = sub { save($title, $set, $filename); ReadMode 0; exit };

my $review_info = get_review_info($set);

ReadMode 3;
eval { run($set, $review_info) };
my $error = $@;
ReadMode 0;

if ($error) {
    print $error;
    print "Save? (y/n) ";
    my $ans = <STDIN>;
    exit unless $ans =~ /y/;
}

save($title, $set, $filename);

sub select_item {
    my ($set, $review_info) = @_;

    my $now = time;

    my @seen   = grep !$_->{new}, grep $_->{title} !~ /^#/, @$set;
    my @unseen = grep  $_->{new}, @$set;

    my @non_interruptible =
        grep $_->{interrupt_tolerance} <= $_->{interrupted_seconds},
        @seen;

    return $non_interruptible[0] if @non_interruptible;

    my @due =
        map $_->[0],
        sort { $a->[1] <=> $b->[1] }
        map [ $_, $_->{interrupt_tolerance} - $_->{interrupted_seconds} ],
        grep $_->{due} < $now,
        @seen;

    return $due[0] if @due;

    my $next = $review_info->{num_new} > 0 ? $unseen[0] : undef;

    return $next if $next;

    my $wait;
    my @candidates;
    for my $item (@seen) {
        my $_wait = $item->{due} - $now;
        $wait //= $_wait;
        if ($_wait == $wait) {
            push @candidates, $item;
        }
        elsif ($_wait < $wait) {
            $wait = $_wait;
            @candidates = ($item);
        }
    }

    return $candidates[0];
}

sub on_reviewed {
    my ($set, $item, %params) = @_;

    my $displayed_time = $params{displayed_time};
    my $answered_time  = $params{answered_time};
    my $correct_answer = $params{correct_answer};

    my $interval =
        $item->{new}     ? 2 :
        !$correct_answer ? 2 :
        ($displayed_time - $item->{last_review}) * $item->{ease};

    $item->{due} = $answered_time + $interval;
    $item->{last_review} = $answered_time;

    for my $_item (@$set) {
        next if $_item->{new};
        next if $_item->{id} == $item->{id};
        $_item->{interrupted_seconds} += $answered_time - $displayed_time;
    }

    $item->{interrupted_seconds} = 0;
    $item->{interrupt_tolerance} =
        $interval <= 8 ? 0 :
        #$interval <= 60 ? 20 :
        $interval;

    delete $item->{new};
}

sub run {
    my ($set, $review_info) = @_;

    my $screen = [];
    my $last_id = 0;

    while (1) {
        my $item = select_item($set, $review_info);
        return unless $item;

        $review_info->{num_new}-- if $item->{new};

        my $wait = ($item->{due} // 0) - time;

        if ($wait > 0) {
            print "\n" x 24;
            print "$wait second rest\n";
            sleep $wait;
            print join '', map $_.$/, @$screen;
        }

        if ($item->{id} <= $last_id) {
            print "\n" x 24;
            @$screen = map "$set->[$_]{title} $set->[$_]{string}", 0..$item->{id}-1;
            print join '', map $_.$/, @$screen;
        }
        elsif ($item->{id} > @$screen) {
            for (@$screen..$item->{id}-1) {
                my $string = "$set->[$_]{title} $set->[$_]{string}";
                push @$screen, $string;
                print $string.$/;
            }
        }

        {
            print "" x length("$set->[$last_id]{title} $set->[$last_id]{string}");
            print "[2K";
            my $prompt = $item->{title}." ?? ";
            print $prompt;
            my $review_time = time;
            return if 'q' eq ReadKey 0;
            print "" x length($prompt);
            print " " x length($prompt);
            print "" x length($prompt);
            print "$item->{title} $item->{string}";
            push @$screen, "$item->{title} $item->{string}";
            my $ans = ReadKey 0;
            return if 'q' eq $ans;
            on_reviewed($set, $item,
                displayed_time => $review_time,
                answered_time  => time,
                correct_answer => (ord($ans) == 127 ? 0 : 1),
            );
            print "\n";
        }

        $last_id = $item->{id};
    }
}

sub get_review_info {
    my ($set) = @_;
    my ($n, $due, $new) = (0, 0, 0);
    my $now = time;
    for (@$set) {
        $n++;
        $due++ if $_->{title} !~ /^#/ && $_->{due} && $_->{due} < $now;
        $new++ if $_->{new};
    }
    print "$n items\n\t$due due\n\t$new new\n\n";
    my @new = grep $_->{new}, @$set;
    print "Next few due:\n".join('', map "    $_->{string}\n", grep defined, @new[0..5])."\n";
    print "Take how many new? ";

    my $num_new = <STDIN>; chomp $num_new;

    print "\n" x 24;

    return {
        num_new => $num_new,
    };
}

sub save {
    my ($title, $set, $filename) = @_;
    print "\nSaving\n";
    open my $f, ">$filename";

    print $f "MEM -- $title\n";

    for my $line (@$set) {

        $line->{string} =~ s/^\[36;m//;
        $line->{string} =~ s/\[0;m$//;
        $line->{string} =~ s/\n/\\n/g;
        $line->{title} =~ s/\n/\\n/g;

        if ($line->{new}) {
            print $f "$line->{title}\t$line->{string}\n";
        }
        else {
            my $string = $line->{string};
            $string =~ s/\n/\\n/g;

            my @meta;
            push @meta, "due=$line->{due}";
            push @meta, "ease=$line->{ease}";
            push @meta, "last_review=$line->{last_review}";
            print $f "$line->{title}\t$line->{string}\t".join(',', @meta)."\n";
        }
    }

    close $f;
}

sub load {
    my ($filename) = @_;
    my ($id, $now, @set) = (0, time);

    open my $file, "<$filename";

    my $title_line = <$file>;
    return load_legacy($filename, $title_line, $file) if $title_line eq "\$VAR1 = [\n";

    $title_line =~ /\AMEM -- (.*)/ or die "Bad file type\n";
    my $title = $1;

    while (<$file>) {
        chomp;

        my %meta;

        if (/\A(.*?)\t(.*?)(?:\t(.*))?\z/) {
            my ($title, $line, $meta) = ($1, $2, $3);

            %meta = map { split /=/ } split /,/, $meta if  $meta;
            %meta = (new => 1)                         if !$meta;

            ($meta{title} = $title) =~ s/\\n/\n/g;
            ($meta{string} = $line) =~ s/\\n/\n/g;

            $meta{string} = "[36;m$meta{string}[0;m";

            $meta{ease} //= 2;

            if ($meta{new}) {
                $meta{interrupt_tolerance} = 0;
            }
            else {
                my $scheduled_interval = $meta{due} - $meta{last_review};
                my $actual_interval    = $now - $meta{last_review};

                if ($actual_interval > 1.5 * $scheduled_interval) {
                    $meta{probably_forgetten} = 1;
                    $meta{interrupt_tolerance} = 0;
                }
                elsif ($scheduled_interval <= 30) {
                    $meta{interrupt_tolerance} = 0;
                }
                elsif ($scheduled_interval <= 60) {
                    $meta{interrupt_tolerance} = 20;
                }
                else {
                    $meta{interrupt_tolerance} = max($actual_interval, $scheduled_interval);
                }
            }

            $meta{interrupted_seconds} = $now - ($meta{last_review} // 0);
        }

        $meta{id} = $id++;

        push @set, \%meta;
    }
    return ($title, \@set);
}

sub load_legacy {
    my ($filename, $title_line, $file) = @_;

    my $content = $title_line . do { local $/; <$file> };
    our $VAR1;
    eval $content;
    die $@ if $@;

    my @set;
    my ($now, $id) = (time, 0);
    for my $item (@$VAR1) {
        my $title = $item->{title};
        my $line = $item->{string};

        my %meta = (
            title  => $title,
            string => $line,
            id     => $id++,
        );

        if ($item->{last_review}) {
            $meta{due} = $item->{due};
            $meta{ease} = $item->{ease};
            $meta{last_review} = $item->{last_review};
        }
        else {
            $meta{new} = 1;
            $meta{ease} = 2;
        }

        if ($meta{new}) {
            $meta{interrupt_tolerance} = 0;
        }
        else {
            my $scheduled_interval = $meta{due} - $meta{last_review};
            my $actual_interval    = $now - $meta{last_review};

            if ($actual_interval > 1.5 * $scheduled_interval) {
                $meta{probably_forgetten} = 1;
                $meta{interrupt_tolerance} = 0;
            }
            elsif ($scheduled_interval <= 30) {
                $meta{interrupt_tolerance} = 0;
            }
            elsif ($scheduled_interval <= 60) {
                $meta{interrupt_tolerance} = 20;
            }
            else {
                $meta{interrupt_tolerance} = max($actual_interval, $scheduled_interval);
            }
        }

        $meta{interrupted_seconds} = $now - ($meta{last_review} // 0);

        push @set, \%meta;
    }

    return ($filename, \@set);
}

sub max {
    my $max;
    for (@_) {
        $max //= $_;
        $max = $_ if $_ > $max;
    }
    return $max;
}

=head1 AUTHOR

Grant Street Group, C<< <developers@grantstreet.com> >>

=head1 COPYRIGHT

Copyright 2015 Grant Street Group

=head1 LICENSE

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.

=cut
