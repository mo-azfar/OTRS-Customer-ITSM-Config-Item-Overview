# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (AGPL). If you
# did not receive this file, see http://www.gnu.org/licenses/agpl.txt.
# --

package Kernel::Modules::CustomerITSMConfigItem;

use strict;
use warnings;

use Kernel::Language qw(Translatable);
use Kernel::System::VariableCheck qw(:all);

our $ObjectManagerDisabled = 1;

sub new {
    my ( $Type, %Param ) = @_;

    # allocate new hash for object
    my $Self = {%Param};
    bless( $Self, $Type );

    return $Self;
}


sub Run {
    my ( $Self, %Param ) = @_;
	
	 # get config of frontend module
    $Self->{Config} = $Kernel::OM->Get('Kernel::Config')->Get("$Self->{Action}");

    # get config data
    $Self->{SearchLimit} = $Self->{Config}->{SearchLimit} || 10000;

    my $SessionObject = $Kernel::OM->Get('Kernel::System::AuthSession');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');
	
	# check subaction
    if ( !$Self->{Subaction} ) {
        return $LayoutObject->Redirect(
            OP => 'Action='.$Self->{Action}.';Subaction=MyCI;Filter=All',
        );
    }

	# check needed CustomerID
    if ( !$Self->{UserCustomerID} ) {
        my $Output = $LayoutObject->CustomerHeader( Title => 'Error' );
        $Output .= $LayoutObject->CustomerError( Message => 'Need CustomerID!' );
        $Output .= $LayoutObject->CustomerFooter();
        return $Output;
    }
	
    # store last screen, used for backlinks
    $SessionObject->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'LastScreenView',
        Value     => $Self->{RequestedURL},
    );

    # store last screen overview
    $SessionObject->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'LastScreenOverview',
        Value     => $Self->{RequestedURL},
    );

    # get param object
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');
	
	 # get default parameters, try to get filter (ClassID) from session if not given as parameter
    $Self->{Filter} = $ParamObject->GetParam( Param => 'Filter' )
        || $Self->{AgentITSMConfigItemClassFilter}
        || '';
    $Self->{View} = $ParamObject->GetParam( Param => 'View' ) || '';

    # store filter (ClassID) in session
    $SessionObject->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'AgentITSMConfigItemClassFilter',
        Value     => $Self->{Filter},
    );

    # get sorting parameters
    my $SortBy = $ParamObject->GetParam( Param => 'SortBy' ) || 'Number';

    # get ordering parameters
    my $OrderBy = $ParamObject->GetParam( Param => 'OrderBy' ) || 'Up';

    # set Sort and Order by as Arrays
    my @SortByArray  = ($SortBy);
    my @OrderByArray = ($OrderBy);
	
	
	 # get general catalog object
    my $GeneralCatalogObject = $Kernel::OM->Get('Kernel::System::GeneralCatalog');

    # get class list
    my $ClassList = $GeneralCatalogObject->ItemList(
        Class => 'ITSM::ConfigItem::Class',
    );

    # get possible deployment state list for config items to be shown
    my $StateList = $GeneralCatalogObject->ItemList(
        Class       => 'ITSM::ConfigItem::DeploymentState',
        Preferences => {
            Functionality => [ 'preproductive', 'productive' ],
        },
    );

    # set the deployment state IDs parameter for the search
    my $DeplStateIDs;
    for my $DeplStateKey ( sort keys %{$StateList} ) {
        push @{$DeplStateIDs}, $DeplStateKey;
    }
	
	# to store the default class
    my $ClassIDAuto = '';

    # to store the NavBar filters
    my %Filters;

    # define position of the filter in the frontend
    my $PrioCounter = 1000;

    # to store the total number of config items in all classes that the user has access
    my $TotalCount;

    # to store all the clases that the user has access, used in search for filter 'All'
    my $AccessClassList;

	# define custmer id and custome ruser field based on subaction
    my $SearchField;
	my $SearchValue;
	my $Title;
	
	if ( $Self->{Subaction} eq "MyCI")
	{
		$SearchField = $Self->{Config}->{'CustomerUserField'};
		$SearchValue = $Self->{UserLogin};
		$Title = "My Config Item";
	}
	elsif ( $Self->{Subaction} eq "CompanyCI")
	{
		$SearchField = $Self->{Config}->{'CustomerIDField'};
		$SearchValue = $Self->{UserCustomerID};
		$Title = "Company Config Item";
	}

    # my config item object
    my $ConfigItemObject = $Kernel::OM->Get('Kernel::System::ITSMConfigItem');

	my %ConfigItemIDsByClassID;
	 
	CLASSID:
    for my $ClassID ( sort { ${$ClassList}{$a} cmp ${$ClassList}{$b} } keys %{$ClassList} ) {

		# search config items which have the CustomerID / current customer user
        $ConfigItemIDsByClassID{$ClassID} = $ConfigItemObject->ConfigItemSearchExtended(
							   
            ClassIDs         => [$ClassID],
            DeplStateIDs     => $DeplStateIDs,
            OrderBy          => \@SortByArray,
            OrderByDirection => \@OrderByArray,
            Limit            => $Self->{SearchLimit},
            What             => [
                {
                    "[1]{'Version'}[1]{'$SearchField'}[1]{'Content'}" => $SearchValue,
                },
            ],
        );
        next CLASSID if !@{ $ConfigItemIDsByClassID{$ClassID} };

        # insert this class to be passed as search parameter for filter 'All'
        push @{$AccessClassList}, $ClassID;

        # count all records of this class
         my $ClassCount = scalar @{ $ConfigItemIDsByClassID{$ClassID} };

        # add the config items number in this class to the total
        $TotalCount += $ClassCount;

        # increase the PrioCounter
        $PrioCounter++;

        # add filter with params for the search method
        $Filters{$ClassID} = {
            Name   => $ClassList->{$ClassID},
            Prio   => $PrioCounter,
            Count  => $ClassCount,
            Search => {
                ClassIDs         => [$ClassID],
                DeplStateIDs     => $DeplStateIDs,
                OrderBy          => \@SortByArray,
                OrderByDirection => \@OrderByArray,
                Limit            => $Self->{SearchLimit},
            },
        };

        # remember the first class id to show this in the overview
        # if no class id was given
        if ( !$ClassIDAuto ) {
            $ClassIDAuto = $ClassID;
        }
    }
	
	# if only one filter exists
    if ( scalar keys %Filters == 1 ) {

        # get the name of the only filter
        my ($FilterName) = keys %Filters;

        # activate this filter
        $Self->{Filter} = $FilterName;
    }
    else {

        # add default filter, which shows all items
        $Filters{All} = {
            Name   => 'All',
            Prio   => 1000,
            Count  => $TotalCount,
            Search => {
                ClassIDs         => $AccessClassList,
                DeplStateIDs     => $DeplStateIDs,
                OrderBy          => \@SortByArray,
                OrderByDirection => \@OrderByArray,
                Limit            => $Self->{SearchLimit},
            },
        };

        # if no filter was selected activate the filter for the default class
        if ( !$Self->{Filter} ) {
            $Self->{Filter} = $ClassIDAuto;
        }
    }

    # check if filter is valid
    if ( !$Filters{ $Self->{Filter} } ) {
        return $LayoutObject->ErrorScreen(
            Message => Translatable('No access to Class is given!'),
            Comment => Translatable('Please contact the administrator.'),
        );
    }

    # investigate refresh
    my $Refresh = $Self->{UserRefreshTime} ? 60 * $Self->{UserRefreshTime} : undef;

    # output header
    my $Output = $LayoutObject->CustomerHeader(
        Title   => Translatable($Title),
        Refresh => $Refresh,
    );
    $Output .= $LayoutObject->CustomerNavigationBar();
    $LayoutObject->Print( Output => \$Output );
    $Output = '';

	# find out which columns should be shown
    my @ShowColumns;
	
	if ( $Self->{Config}->{ShowColumns} ) {

        # get all possible columns from config
        my %PossibleColumn = %{ $Self->{Config}->{ShowColumns} };

        # show column "Class" if filter 'All' is selected
        if ( $Self->{Filter} eq 'All' ) {
            $PossibleColumn{Class} = '1';
        }

        # get the column names that should be shown
        COLUMNNAME:
        for my $Name ( sort keys %PossibleColumn ) {
            next COLUMNNAME if !$PossibleColumn{$Name};
            push @ShowColumns, $Name;
        }
    }

    # get the configured columns and reorganize them by class name
    if (
        IsArrayRefWithData( $Self->{Config}->{ShowColumnsByClass} )
        && $Self->{Filter}
        && $Self->{Filter} ne 'All'
        )
    {

        my %ColumnByClass;
        NAME:
        for my $Name ( @{ $Self->{Config}->{ShowColumnsByClass} } ) {
            my ( $Class, $Column ) = split /::/, $Name, 2;

            next NAME if !$Column;

            push @{ $ColumnByClass{$Class} }, $Column;
        }

        # check if there is a specific column config for the selected class
        my $SelectedClass = $ClassList->{ $Self->{Filter} };
        if ( $ColumnByClass{$SelectedClass} ) {
            @ShowColumns = @{ $ColumnByClass{$SelectedClass} };
        }
    }


    # display all navbar filters
    my %NavBarFilter;
    for my $Filter ( sort keys %Filters ) {

        # display the navbar filter
        $NavBarFilter{ $Filters{$Filter}->{Prio} } = {
            Filter => $Filter,
            %{ $Filters{$Filter} },
        };
    }
	
	# show header filter
    for my $Key ( sort keys %NavBarFilter ) {
        $LayoutObject->Block(
            Name => 'FilterHeader',
            Data => {
                %{ $NavBarFilter{$Key} },
            },
        );
    }
	
	my $ConfigItemIDs;

    # already cached
    if ( $ConfigItemIDsByClassID{ $Self->{Filter} } ) {
        $ConfigItemIDs = $ConfigItemIDsByClassID{ $Self->{Filter} };
    }
	# make a new search
    else {
        $ConfigItemIDs = $ConfigItemObject->ConfigItemSearchExtended(
            %{ $Filters{ $Self->{Filter} }->{Search} },
            What => [
                {
                    "[1]{'Version'}[1]{'$SearchField'}[1]{'Content'}" => $SearchValue,
                },
            ],
        );
    }

	    # show customer CI data
    if ( @{$ConfigItemIDs} ) {

        if (@ShowColumns) {

            # set headers
            for my $ColumnName (@ShowColumns) {

                # create needed variables
                my $CSS = '';
                my $SetOrderBy;

                # remove ID if necessary
                if ($SortBy) {
                    $SortBy = ( $SortBy eq 'InciStateID' )
                        ? 'CurInciState'
                        : ( $SortBy eq 'DeplStateID' ) ? 'CurDeplState'
                        : ( $SortBy eq 'ClassID' )     ? 'Class'
                        : ( $SortBy eq 'ChangeTime' )  ? 'LastChanged'
                        :                                $SortBy;
                }

                # set the correct Set CSS class and order by link
                if ( $SortBy && ( $SortBy eq $ColumnName ) ) {
                    if ( $OrderBy && ( $OrderBy eq 'Up' ) ) {
                        $SetOrderBy = 'Down';
                        $CSS .= ' SortDescending';
                    }
                    else {
                        $SetOrderBy = 'Up';
                        $CSS .= ' SortAscending';
                    }
                }
                else {
                    $SetOrderBy = 'Up';
                }

                $LayoutObject->Block(
                    Name => 'Record' . $ColumnName . 'Header',
                    Data => {
                        CSS     => $CSS,
						OrderBy => $SetOrderBy,
                        Filter  => $Self->{Filter},
                    },
                );
            }
        }

        # define incident signals, needed for CI flags
        my %InciSignals = (
            operational => 'greenled',
            warning     => 'yellowled',
            incident    => 'redled',
        );

        ConfigItemID:
        for my $ConfigItemID ( @{$ConfigItemIDs} ) {

            # get config item data
            my $ConfigItem = $ConfigItemObject->VersionGet(
                ConfigItemID => $ConfigItemID,
                XMLDataGet   => 0,
            );

            next ConfigItemID if !$ConfigItem;

            # add block
            $LayoutObject->Block(
                Name => 'Record',
                Data => {},
            );

            if (@ShowColumns) {
                COLUMN:
                for my $ColumnName (@ShowColumns) {
                   $LayoutObject->Block(
                        Name => 'Record' . $ColumnName,
                        Data => {
                            %{$ConfigItem},
                            CurInciSignal => $InciSignals{ $ConfigItem->{CurInciStateType} },
                        },
                    );

                    # show links if available
                    if (
                        $ColumnName eq 'Number'
                        && $Kernel::OM->Get('Kernel::Config')->Get('CustomerFrontend::Module')->{CustomerITSMConfigItemZoom}
                        )
                    {
                        $LayoutObject->Block(
                            Name => 'Record' . $ColumnName . 'LinkStart',
                            Data => {
                                %{$ConfigItem},
                            },
                        );
                        $LayoutObject->Block(
                            Name => 'Record' . $ColumnName . 'LinkEnd',
                            Data => {
                                %{$ConfigItem},
                            },
                        );
                    }
                }
            }

        }
    }

    # otherwise show no data found message
    else {
        $LayoutObject->Block(
            Name => 'NoDataFoundMsg',
            Data => {},
        );
    }

	$Output .= $LayoutObject->Output(
        TemplateFile => 'CustomerITSMConfigItem',
        Data         => \%Param,
    );
	
    # add footer
    $Output .= $LayoutObject->CustomerFooter();

    return $Output;
	
}

1;