# This software comes with ABSOLUTELY NO WARRANTY. For details, see
# the enclosed file COPYING for license information (GPL). If you
# did not receive this file, see https://www.gnu.org/licenses/gpl-3.0.txt.
# --

package Kernel::Modules::CustomerITSMConfigItemZoom;

use strict;
use warnings;

## nofilter(TidyAll::Plugin::OTRS::Migrations::OTRS6::SysConfig)

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
	
	my $ConfigObject = $Kernel::OM->Get('Kernel::Config');
    my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

    # get param object
    my $ParamObject = $Kernel::OM->Get('Kernel::System::Web::Request');

    # get params
    my $ConfigItemNumber = $ParamObject->GetParam( Param => 'ConfigItemNumber' ) || 0;

    # check needed stuff
    if ( !$ConfigItemNumber ) {
       return $LayoutObject->CustomerErrorScreen(
            Message => Translatable('No ConfigItem Number is given!'),
            Comment => Translatable('Please contact the administrator.'),
        );
    }

    # get needed object
    my $ConfigItemObject = $Kernel::OM->Get('Kernel::System::ITSMConfigItem');
	
	my $ConfigItemID = $ConfigItemObject->ConfigItemLookup(
		ConfigItemNumber => $ConfigItemNumber,
	);

	#if not exist, just let customer know taht their dont have an access to config item 
    if ( !$ConfigItemID ) {
        return $LayoutObject->CustomerErrorScreen(
            Message => $LayoutObject->{LanguageObject}->Translate( 'You dont have a permission to access this ConfigItem#%s!', $ConfigItemNumber ),
			Comment => Translatable('Please contact the administrator.'),
        );
    }
	
    # get content
    my $ConfigItem = $ConfigItemObject->ConfigItemGet(
        ConfigItemID => $ConfigItemID,
    );

    # get version list
    my $VersionList = $ConfigItemObject->VersionZoomList(
        ConfigItemID => $ConfigItemID,
    );
    if ( !$VersionList->[0]->{VersionID} ) {
       return $LayoutObject->CustomerErrorScreen(
            Message => $LayoutObject->{LanguageObject}->Translate( 'No version found for ConfigItemID %s!', $ConfigItemID ),
            Comment => Translatable('Please contact the administrator.'),
        );
    }

    # set version id
    my $VersionID = $VersionList->[-1]->{VersionID};

	# get the name of the CI attribute where the CustomerID or username is stored
    my $CustomerUserField = $ConfigObject->Get('CustomerITSMConfigItem::CustomerUserField') || 'Owner';
	
	# get the name of the CI attribute where the CustomerID or username is stored
    my $CustomerIDField = $ConfigObject->Get('CustomerITSMConfigItem::CustomerIDField') || 'CustomerID';

    # get version
    my $Version = $ConfigItemObject->VersionGet(
        VersionID => $VersionID,
    );
	
	# check for customer access to his/her config item
    my $HasAccess;
    if (
        IsHashRefWithData($Version)
        && IsArrayRefWithData( $Version->{XMLData} )
        && IsHashRefWithData( $Version->{XMLData}->[1] )
        && IsArrayRefWithData( $Version->{XMLData}->[1]->{Version} )
        && IsHashRefWithData( $Version->{XMLData}->[1]->{Version}->[1] )
        && IsArrayRefWithData( $Version->{XMLData}->[1]->{Version}->[1]->{$CustomerUserField} )
        && IsHashRefWithData( $Version->{XMLData}->[1]->{Version}->[1]->{$CustomerUserField}->[1] )
        && IsStringWithData(
            $Version->{XMLData}->[1]->{Version}->[1]->{$CustomerUserField}->[1]->{Content}
        )
        && $Version->{XMLData}->[1]->{Version}->[1]->{$CustomerUserField}->[1]->{Content} eq
        $Self->{UserLogin}
        )
    {
        $HasAccess = 1;
    }
	elsif (
        IsHashRefWithData($Version)
        && IsArrayRefWithData( $Version->{XMLData} )
        && IsHashRefWithData( $Version->{XMLData}->[1] )
        && IsArrayRefWithData( $Version->{XMLData}->[1]->{Version} )
        && IsHashRefWithData( $Version->{XMLData}->[1]->{Version}->[1] )
        && IsArrayRefWithData( $Version->{XMLData}->[1]->{Version}->[1]->{$CustomerIDField} )
        && IsHashRefWithData( $Version->{XMLData}->[1]->{Version}->[1]->{$CustomerIDField}->[1] )
        && IsStringWithData(
            $Version->{XMLData}->[1]->{Version}->[1]->{$CustomerIDField}->[1]->{Content}
        )
        && $Version->{XMLData}->[1]->{Version}->[1]->{$CustomerIDField}->[1]->{Content} eq
        $Self->{UserCustomerID}
        )
    {
        $HasAccess = 1;
    }
	
    if ( !$HasAccess ) {
	
        # error page
        return $LayoutObject->CustomerErrorScreen(
            Message => 'Can\'t show item, no access rights are given!',
            Comment => 'Please contact the administrator.',
        );
    }
	
    # get last version
    my $LastVersion = $VersionList->[-1];
	
    # set incident signal
    my %InciSignals = (
        Translatable('operational') => 'greenled',
        Translatable('warning')     => 'yellowled',
        Translatable('incident')    => 'redled',
    );
	
	# get last class definition in order to know the fields that should be hidden in customer
    #     interface
    my $LastDefinition = $ConfigItemObject->DefinitionGet(
        ClassID => $Version->{ClassID},
    );
	
    # output header
    my $Output = $LayoutObject->CustomerHeader( Value => $ConfigItem->{Number} );
    $Output .= $LayoutObject->CustomerNavigationBar();
	
    # show back link
    if ( $Self->{LastScreenOverview} ) {
        $LayoutObject->Block(
            Name => 'Back',
            Data => \%Param,
        );
    }
	
    if (
        $Version
        && ref $Version eq 'HASH'
        && $Version->{XMLDefinition}
        && $Version->{XMLData}
        && ref $Version->{XMLDefinition} eq 'ARRAY'
        && ref $Version->{XMLData} eq 'ARRAY'
        && $Version->{XMLData}->[1]
        && ref $Version->{XMLData}->[1] eq 'HASH'
        && $Version->{XMLData}->[1]->{Version}
        && ref $Version->{XMLData}->[1]->{Version} eq 'ARRAY'
        )
    {
	
        # transform ascii to html
        $Version->{Name} = $LayoutObject->Ascii2Html(
            Text           => $Version->{Name},
            HTMLResultMode => 1,
            LinkFeature    => 1,
        );
	
        # output name
        $LayoutObject->Block(
            Name => 'Data',
            Data => {
                Name        => Translatable('Name'),
                Description => Translatable('The name of this config item'),
                Value       => $Version->{Name},
                Identation  => 10,
				Class       => 'ParentAttribute',
            },
        );
	
        # output deployment state
        $LayoutObject->Block(
            Name => 'Data',
            Data => {
                Name        => Translatable('Deployment State'),
                Description => Translatable('The deployment state of this config item'),
                Value       => $LayoutObject->{LanguageObject}->Translate(
                    $Version->{DeplState},
                ),
                Identation => 10,
				Class      => 'ParentAttribute',
            },
        );
	
        # output incident state
        $LayoutObject->Block(
            Name => 'Data',
            Data => {
                Name        => Translatable('Incident State'),
                Description => Translatable('The incident state of this config item'),
                Value       => $LayoutObject->{LanguageObject}->Translate(
                    $Version->{InciState},
                ),
                Identation => 10,
				Class      => 'ParentAttribute',
            },
        );
	
        # start xml output
        $Self->_XMLOutput(
            XMLDefinition => $Version->{XMLDefinition},
            XMLData       => $Version->{XMLData}->[1]->{Version}->[1],
			XMLLastDefinition => $LastDefinition->{DefinitionRef},
        );
    }
	
	# output meta block
    $LayoutObject->Block(
        Name => 'Meta',
        Data => {
            %{$LastVersion},
            %{$ConfigItem},
            CurInciSignal => $InciSignals{ $LastVersion->{CurInciStateType} },
        },
    );
	
	##TODO: WIP
    # get linked objects
    #my $LinkListWithData = $Kernel::OM->Get('Kernel::System::LinkObject')->LinkListWithData(
    #    Object => 'ITSMConfigItem',
    #    Key    => $ConfigItemID,
    #    State  => 'Valid',
    #    UserID => $Self->{UserID},
    #);
	#
    ## get link table view mode
    #my $LinkTableViewMode = $ConfigObject->Get('LinkObject::ViewMode');
	#
    ## create the link table
    #my $LinkTableStrg = $LayoutObject->LinkObjectTableCreate(
    #    LinkListWithData => $LinkListWithData,
    #    ViewMode         => $LinkTableViewMode,
    #    Object           => 'ITSMConfigItem',
    #    Key              => $ConfigItemID,
    #);
	#
    ## output the link table
    #if ($LinkTableStrg) {
    #    $LayoutObject->Block(
    #        Name => 'LinkTable' . $LinkTableViewMode,
    #        Data => {
    #            LinkTableStrg => $LinkTableStrg,
    #        },
    #    );
    #}

    my @Attachments = $ConfigItemObject->ConfigItemAttachmentList(
        ConfigItemID => $ConfigItemID,
    );
	
    if (@Attachments) {
	
        # get the metadata of the 1st attachment
        my $FirstAttachment = $ConfigItemObject->ConfigItemAttachmentGet(
            ConfigItemID => $ConfigItemID,
            Filename     => $Attachments[0],
        );
	
        $LayoutObject->Block(
            Name => 'Attachments',
            Data => {
                ConfigItemID => $ConfigItemID,
                Filename     => $FirstAttachment->{Filename},
                Filesize     => $FirstAttachment->{Filesize},
            },
        );
	
        # the 1st attachment was directly rendered into the 1st row's right cell, all further
        # attachments are rendered into a separate row
        ATTACHMENT:
        for my $Attachment (@Attachments) {
	
            # skip the 1st attachment
            next ATTACHMENT if $Attachment eq $Attachments[0];
	
            # get the metadata of the current attachment
            my $AttachmentData = $ConfigItemObject->ConfigItemAttachmentGet(
                ConfigItemID => $ConfigItemID,
                Filename     => $Attachment,
            );
	
            $LayoutObject->Block(
                Name => 'AttachmentRow',
                Data => {
                    ConfigItemID => $ConfigItemID,
                    Filename     => $AttachmentData->{Filename},
                    Filesize     => $AttachmentData->{Filesize},
                },
            );
        }
    }
	
    # handle DownloadAttachment
    if ( $Self->{Subaction} eq 'DownloadAttachment' ) {
	
        # get data for attachment
        my $Filename       = $ParamObject->GetParam( Param => 'Filename' );
        my $AttachmentData = $ConfigItemObject->ConfigItemAttachmentGet(
            ConfigItemID => $ConfigItemID,
            Filename     => $Filename,
        );
	
        # return error if file does not exist
        if ( !$AttachmentData ) {
            $Kernel::OM->Get('Kernel::System::Log')->Log(
                Message  => "No such attachment ($Filename)!",
                Priority => 'error',
            );
            return $LayoutObject->CustomerErrorScreen();
        }
	
        return $LayoutObject->Attachment(
            %{$AttachmentData},
            Type => 'attachment',
        );
    }
	
    # store last screen
    $Kernel::OM->Get('Kernel::System::AuthSession')->UpdateSessionID(
        SessionID => $Self->{SessionID},
        Key       => 'LastScreenView',
        Value     => $Self->{RequestedURL},
    );
	
    # start template output
    $Output .= $LayoutObject->Output(
        TemplateFile => 'CustomerITSMConfigItemZoom',
        Data         => {
            %{$LastVersion},
            %{$ConfigItem},
            CurInciSignal => $InciSignals{ $LastVersion->{CurInciStateType} },
        },
    );
	
    # add footer
    $Output .= $LayoutObject->CustomerFooter();
	
    return $Output;
}

sub _XMLOutput {
    my ( $Self, %Param ) = @_;

    # check needed stuff
    return if !$Param{XMLData};
    return if !$Param{XMLDefinition};
    return if ref $Param{XMLData} ne 'HASH';
    return if ref $Param{XMLDefinition} ne 'ARRAY';

    $Param{Level} ||= 0;
	
	# create a lookup table from the class definition to locate easily each field
    my %LastDefinitionLookup;
    if ( IsArrayRefWithData( $Param{XMLLastDefinition} ) ) {
        %LastDefinitionLookup = map { $_->{Key} => $_ } @{ $Param{XMLLastDefinition} };
    }


    ITEM:
    for my $Item ( @{ $Param{XMLDefinition} } ) {
		
		# skip fields that should be hidden in customer interface
        next ITEM if $Item->{NotForCustomerInterface};

        # skip fields that are mark as hidden in last class definition even if current config item is not updated.
        next ITEM if $LastDefinitionLookup{ $Item->{Key} }->{NotForCustomerInterface};
		
        COUNTER:
        for my $Counter ( 1 .. $Item->{CountMax} ) {

            # stop loop, if no content was given
            last COUNTER if !defined $Param{XMLData}->{ $Item->{Key} }->[$Counter]->{Content};

            # lookup value
            my $Value = $Kernel::OM->Get('Kernel::System::ITSMConfigItem')->XMLValueLookup(
                Item  => $Item,
                Value => $Param{XMLData}->{ $Item->{Key} }->[$Counter]->{Content},
            );

            # get layout object
            my $LayoutObject = $Kernel::OM->Get('Kernel::Output::HTML::Layout');

            # create output string
            $Value = $LayoutObject->ITSMConfigItemOutputStringCreate(
                Value => $Value,
                Item  => $Item,
            );

            # calculate indentation for left-padding css based on 15px per level and 10px as default
            my $Indentation = 10;
			
			# set special class on parent attributes to add decoration by CSS
            my $Class = 'ParentAttribute';

            if ( $Param{Level} ) {
                $Indentation += 15 * $Param{Level};
				$Class = '';
            }

            # output data block
            $LayoutObject->Block(
                Name => 'Data',
                Data => {
                    Name        => $Item->{Name},
                    Description => $Item->{Description} || $Item->{Name},
                    Value       => $Value,
                    Indentation => $Indentation,
					Class       => $Class,
                },
            );

            # start recursion, if "Sub" was found
            if ( $Item->{Sub} ) {
				
				# send only last definition sub items in the recursion
                my $XMLLastDefinition = $LastDefinitionLookup{ $Item->{Key} }->{Sub};
				
                $Self->_XMLOutput(
                    XMLDefinition 		=> $Item->{Sub},
                    XMLData       		=> $Param{XMLData}->{ $Item->{Key} }->[$Counter],
					XMLLastDefinition	=> $XMLLastDefinition,
                    Level         		=> $Param{Level} + 1,
                );
            }
        }
    }

    return 1;
}

1;
