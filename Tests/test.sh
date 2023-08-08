#!/bin/bash

#set -x

# Sourcing user-provided env properties
source ../config/envCB.properties

# source main file to access the function
source ../utils.sh

TEMP_DIR=./trash

function loginToPlatform {

	axway auth login
	# retrieve the organizationId of the connected user
	echo ""
	echo "Retrieving the organization ID..."
	PLATFORM_ORGID=$(axway auth list --json | jq -r '.[0] .org .id')
	PLATFORM_TOKEN=$(axway auth list --json | jq -r '.[0] .auth .tokens .access_token ')
	ORGANIZATION_REGION=$(axway auth list --json | jq -r '.[0] .org .region ')
	echo "OK we are good."
}

function testReadingCatalogDocumentation {

	loginToPlatform

	CATALOG_ID="8ac983148850862e0189d16ead1a20d2"
	echo "	Reading Catalog documentation"
	articleContent=$(readCatalogDocumentationFromItsId "$CATALOG_ID" "TEMP VALUE FOR TEST")
	
	if [[ $articleContent == "TEMP VALUE FOR TEST" ]]
	then 
		echo $articleContent
	else
		echo "Something is wrong"
		exit 1
	fi

	articleContent=$(readCatalogDocumentationFromItsId "$CATALOG_ID" "")
	
	if [[ $articleContent == "" ]]
	then
		echo "No documentation found"
	else
		echo "Something is wrong"
		exit 1
	fi
}

function testGetApiServiceInstanceOrdered {

#	CATALOG_APISERVICE="ny-times-articles
	CATALOG_APISERVICE="spacex"
	CATALOG_APISERVICEENV="apigtw-v77"
	axway central get apisi -q "metadata.references.name==$CATALOG_APISERVICE&sort=metadata.audit.createTimestamp%2CDESC" -s $CATALOG_APISERVICEENV -o json > ./apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE-instance.json
	cat ./apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE-instance.json | jq -rc ".[0] | {ard: .spec.accessRequestDefinition, crd: .spec.credentialRequestDefinitions}" > ./apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE-instance-check.json
	ARD=`cat ./apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE-instance-check.json | jq -rc ".ard"`
	CRD=`cat ./apis-$CATALOG_APISERVICEENV-$CATALOG_APISERVICE-instance-check.json | jq -rc ".crd"`

	echo "ARD=$ARD / CRD=$CRD"

	if [[ $ARD != null && $CRD != null ]]
	then
		echo "Good to create AccessRequest"
	else
		echo "Cannot proceed with AccessRequest as missing..."
	fi
}

function testReadingCatalogSubscription {

	loginToPlatform

	CONSUMER_INSTANCE_TITLE="pets3"

	axway central get consumeri -q "title=='$CONSUMER_INSTANCE_TITLE'" -s $CENTRAL_ENVIRONMENT -o json > $TEMP_DIR/consumeri.json
	CATALOG_APISERVICE_REVISION=`cat $TEMP_DIR/consumeri.json | jq -rc ".[0].references.apiServiceRevision"`

	CENTRAL_URL=$(getCentralURL)
	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems?query=%28name==%27'$CONSUMER_INSTANCE_TITLE'%27%29&' 
	# replace spaces with %20 in case the Catalog name has some
	URL=${URL// /%20}
	#echo curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN
	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItem.json
	
	#filter the one that match latestersion to the consumerInstance-references.apiServiceRevision
	CATALOG_ID=`jq --arg FILTER_VALUE "$CATALOG_APISERVICE_REVISION" -r '.[] | select(.latestVersion==$FILTER_VALUE)' $TEMP_DIR/catalogItem.json | jq -r ". | .id"`
	
	# now read the catalog ID
	echo "			CatID=$CATALOG_ID"

	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'?embed=image,properties,revisions,subscription' 
	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItem2.json
}

function sanitizeParenthesisAndSpace {

	#( = %28
	#) = %29
	# space = %20

	# replace parenthesis
 	SANITIZED_VALUE=`echo "$1" | sed 's/[(]/%28/g' | sed 's/[)]/%29/g'`
	#replace space
	SANITIZED_VALUE=${SANITIZED_VALUE// /%20}

	#return sanitized value
	echo $SANITIZED_VALUE
}


########################
# TESTING PURPOSE CURL #
########################

function findCatalogItemFromConsumerInstance {

	loginToPlatform

	#CATALOG_TITLE="nytimes (v7-emt)"
	CATALOG_TITLE="Recurly"
	axway central get consumeri -q "title=='$CATALOG_TITLE'" -o json > $TEMP_DIR/consumeri.json

	APISERVICE_NAME=`cat $TEMP_DIR/consumeri.json | jq -rc ".[] | .references.apiService"`
	APISERVICE_ENVNAME=`cat $TEMP_DIR/consumeri.json | jq -rc ".[] | .metadata.scope.name"`

	echo "$APISERVICE_NAME / $APISERVICE_ENVNAME"

	echo "	Finding associated catalog item ($CATALOG_TITLE)..."
	CENTRAL_URL=$(getCentralURL)
	echo "CentralUrl="$CENTRAL_URL
	# query format section: query=(name=='VALUE') -> replace ( and ) by their respective HTML value
	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems?query=%28name==%27'$CATALOG_TITLE'%27%29&' 
	# replace spaces with %20 in case the Catalog name has some
	URL=${URL// /%20}
	#echo "curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItem.json"
	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItem.json
	CATALOG_ID=`cat $TEMP_DIR/catalogItem.json | jq -r ".[0] | .id"`

	echo "CatID=$CATALOG_ID"
	export CATALOG_ID

	# reading details
	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'?embed=image,properties,revisions,subscription' 
	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItem.json

	# reading documentation
	CATALOG_DOCUMENTATION=$(readCatalogDocumentationFromItsId "$CATALOG_ID")
	echo $CATALOG_DOCUMENTATION

#	echo "SED is coming..."
#	sed 's/\\n/\'$'\n''/g' <<<  $DOCUMENTATION > $TEMP_DIR/doc.txt
#	cat $TEMP_DIR/doc.txt

#	CATALOG_ICON="data:image/png;base64,"`cat $TEMP_DIR/catalogItem.json | jq -r "._embedded.image.base64"`
#	echo $CATICON

#	jq -n -f ../jq/asset.jq --arg title "$CONSUMER_INSTANCE_TITLE" --arg description "$CONSUMER_INSTANCE_DESCRIPTION" --arg icon $CATALOG_ICON> $TEMP_DIR/asset.json
#	cat $TEMP_DIR/asset.json

}

function testCURL {
	
	loginToPlatform

	#CATALOG_NAME="SpaceX Graphql APIs"
	CATALOG_TITLE="nytimes (v7-emt)"
	CATALOG_TITLE="calculatrice (Stage: Demo)"
	#CATALOG_NAME="d0999755-c483-11eb-b083-0242ac190007"

	SANITIZE_CATALOG_TITLE=$(sanitizeParenthesisAndSpace "$CATALOG_TITLE")

	#CATALOG_NAME="RollADice (Stage: Demo)"
	#CATALOG_NAME="Parties"

	# read catalog id from catalog name
	echo "	Finding associted catalog item..."
	# query format section: query=(name==VALUE) -> replace ( and ) by their respective HTML value
	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems?query=%28name==%27'$CATALOG_TITLE'%27%29' 

	#URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems' 
	# replace spaces with %20 in case the Catalog name has some
	URL=${URL// /%20}
	echo $URL
	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItem.json
	CATALOG_ID=`cat $TEMP_DIR/catalogItem.json | jq -r ".[0] | .id"`
	echo $CATALOG_ID

	echo reading dependencies
	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'?embed=image,properties,revisions,subscription' 
	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItem.json
	CATALOG_ICON="data:image/png;base64,"`cat $TEMP_DIR/catalogItem.json | jq -r "._embedded.image.base64"`
	echo "Icon=$CATALOG_ICON"

	echo "	Reading associated subscription(s)...."
	curl -s --location --request GET $CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'/subscriptions?query=%28state==ACTIVE%29' --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItemSubscriptions.json
	echo "	Found " `cat $TEMP_DIR/catalogItemSubscriptions.json | jq '.|length'` " ACTIVE subscription(s)"

	cat $TEMP_DIR/catalogItemSubscriptions.json | jq -rc ".[] | {subId: .id, subName: .name, teamId: .owningTeamId, appName: .properties[0].value.appName}"

	echo "	Finding consumer instance"
	#axway central get consumeri -q metadata.references.id==$CATALOG_ID -o json > $TEMP_DIR/consumeri.json
	axway central get consumeri -q title=="$CATALOG_TITLE" -s v7-emt -o json > $TEMP_DIR/consumeri.json


	# Get catalog revisions
#	echo "	Reading associated revision...."
#	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'/revisions'
#	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItemRevisions.json


	# Get catalog relationship
#	echo "	Reading associated relationships...."
#	URL=$CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'/relationships'
#	curl -s --location --request GET ${URL} --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/catalogItemRelationships.json

#	echo "	Reading associated ACTIVE subscription...."
#	curl -s --location --request GET $CENTRAL_URL'/api/unifiedCatalog/v1/catalogItems/'$CATALOG_ID'/subscriptions?query=%28state==ACTIVE%29' --header 'X-Axway-Tenant-Id: '$PLATFORM_ORGID --header 'Authorization: Bearer '$PLATFORM_TOKEN > $TEMP_DIR/subscriptions.json
#	echo "	Found " `cat $TEMP_DIR/subscriptions.json | jq '.|length'` " subscription(s)"



#	cat $TEMP_DIR/catalogItemSubscriptions.json | jq -rc ".[] | {subId: .id, subName: .name, teamId: .owningTeamId, appName: .properties[0].value.appName}" | while IFS= read -r line ; do
		# read subscriptionId, application name, teamId and subscription name
#		SUBSCRIPTION_ID=$(echo $line | jq -r '.subId')
#		SUBSCRIPTION_NAME=$(echo $line | jq -r '.subName')
#		SUBSCRIPTION_OWNING_TEAM=$(echo $line | jq -r '.teamId')
#		SUBSCRIPTION_APP_NAME=$(echo $line | jq -r '.appName')

#		echo "SUBSCRIPTION_APP_NAME=$SUBSCRIPTION_APP_NAME"

#		if [[ $SUBSCRIPTION_APP_NAME == null ]]
#		then
#			echo "			==> no application found, cannot create ManagedApplication / AccessRequest"
#		else
#			echo "			Create managed application $SUBSCRIPTION_APP_NAME...."
#		fi

#	done # loop over subscription
}

function testMarketplaceAPIs {

	loginToPlatform

	MP_URL=$(readMarketplaceUrlFromMarketplaceName)
	echo "MP_URL=$MP_URL"

	#echo "	Testing the MP product search..."
#	CATALOG_TITLE="nytimes (v7-emt)"
#	SANITIZE_CATALOG_TITLE=${CATALOG_TITLE// /%20}
#	PRODUCT_ID=$(getFromMarketplace "$MP_URL/api/v1/products?limit=10&offset=0&search=$SANITIZE_CATALOG_TITLE&sort=-lastVersion.metadata.createdAt%2C%2Bname" ".items[0].id")
#	echo "		Found product:" $PRODUCT_ID

#	echo "	Testing the MP product version search..."
#	CONTENT=$(getFromMarketplace "$MP_URL/api/v1/products?limit=10&offset=0&search=$SANITIZE_CATALOG_NAME&sort=-lastVersion.metadata.createdAt%2C%2Bname")
#	echo "		Found latest product version" `echo $CONTENT | jq -r ".items[0].latestVersion.id"`
#	PRODUCT_ID=`echo $CONTENT | jq -r ".items[0].id"`
#	echo "		Found product:" $PRODUCT_ID

#	SUBSCRIPTION_APP_NAME="Medical House"
#	CONTENT=$(getFromMarketplace "$MP_URL/api/v1/applications?limit=10&offset=0&search=$SUBSCRIPTION_APP_NAME&sort=-metadata.modifiedAt%2C%2Bname" ".items[0].id")
#	echo "$SUBSCRIPTION_APP_NAME -> $CONTENT"

#	MP_PRODUCT_PLAN_ID=$(getFromMarketplace "$MP_URL/api/v1/products/$PRODUCT_ID/plans" ".items[0].id")
#	echo "		Found product plan ID:" $MP_PRODUCT_PLAN_ID

#	echo "	Testing the MP product plan search..."
#	PLAN_ID=$(getFromMarketplace "$MP_URL/api/v1/products/$PRODUCT_ID/plans" ".items[0].id")
#	echo "		Found plan:" $PLAN_ID

#	echo "	Testing creating MP subscription"
#	postToMarketplace "$MP_URL/api/v1/subscriptions" $TEMP_DIR/product-spacex-subscription.json

	MP_PRODUCT_ID=8a2e8d44882b74fd01882f41c7a3091f
	SUBSCRIPTION_OWNING_TEAM=e4ec6c3369cdafa50169d9f8a6600dcb
	CONTENT=$(getFromMarketplace "$MP_URL/api/v1/subscriptions?product.id=$MP_PRODUCT_ID&owner.id=$SUBSCRIPTION_OWNING_TEAM")
	NB_SUBSCRIPTION=`echo $CONTENT | jq '.items|length'`
	echo "Found: $NB_SUBSCRIPTION subscription(s)"

}

function testErrorFucntion {
	error_post "No error" "./noErrorFile.json"
	error_post "Error found" "./errorFile.json"
}

function testParameter {

 	# Testing parameters
	if [[ $CLIENT_ID == "" ]]
	then
		echo "No arguments supplied => login via browser"
		#axway auth login
	else
		echo "Service account supplied => login headless"
		#axway auth login --client-id $1 --secret-file "$2" --username $3
	fi

	if [[ $PUBLISH_TO_MARKETPLACES == "Y" ]]
	then
		# Publishing to the Marketplace(s)
		echo "	Publishing product into Marketplaces..."
	fi
}

function testOwner {

	CONSUMER_INSTANCE_OWNER_ID=$(cat $TEMP_DIR/objectToMigrateOwner.json | jq -rc ".[] | {id: .metadata.id, name: .name, title: .title, description: .spec.description, apiserviceName: .references.apiService, tags: .tags, environment: .metadata.scope.name, ownerId: .owner.id}" | jq -r '.ownerId')

	echo "|"$CONSUMER_INSTANCE_OWNER_ID"|"

	echo "if [[ $CONSUMER_INSTANCE_OWNER_ID == null ]]"
	if [[ $CONSUMER_INSTANCE_OWNER_ID == null ]]
	then
		echo "		without owner"
	else
		echo "		with owningTeam : $CONSUMER_INSTANCE_OWNER_ID"
	fi

	echo "if [[ $CONSUMER_INSTANCE_OWNER_ID != null ]]"
	if [[ $CONSUMER_INSTANCE_OWNER_ID != null ]]
	then
		echo "	with owningTeam :  $CONSUMER_INSTANCE_OWNER_ID"
	else
		echo "	without owner"
	fi
}


function testNoOwner {

	CONSUMER_INSTANCE_OWNER_ID=$(cat $TEMP_DIR/objectToMigrateNoOwner.json | jq -rc ".[] | {id: .metadata.id, name: .name, title: .title, description: .spec.description, apiserviceName: .references.apiService, tags: .tags, environment: .metadata.scope.name, ownerId: .owner.id}" | jq -r '.ownerId')

	echo "|"$CONSUMER_INSTANCE_OWNER_ID"|"

	echo "if [[ $CONSUMER_INSTANCE_OWNER_ID == null ]]"
	if [[ $CONSUMER_INSTANCE_OWNER_ID == null ]]
	then
		echo "		without owner"
	else
		echo "		with owningTeam : $CONSUMER_INSTANCE_OWNER_ID"
	fi

	echo "if [[ $CONSUMER_INSTANCE_OWNER_ID != null ]]"
	if [[ $CONSUMER_INSTANCE_OWNER_ID != null ]]
	then
		echo "	with owningTeam :  $CONSUMER_INSTANCE_OWNER_ID"
	else
		echo "	without owner"
	fi
}

function testJQ {
	# various jq testing
#	jq --arg str "1.435" -n '$str|tonumber'
#	jq -n --argjson number 300 '{"number": $number}'

#	jq '.address = "new address"' ./test.json
#	jq '.enfant.age = 100' ./test.json
#	jq '.enfant.age = (env.PLAN_QUOTA|tonumber)' ./test.json

	# Update quota testing
#	PLAN_QUOTA=`echo $PLAN_QUOTA`
#	export PLAN_QUOTA
#	echo $PLAN_QUOTA
#	jq '.spec.pricing.limit.value=($ENV.PLAN_QUOTA|tonumber)' ./product-plan-quota.json > ./product-plan-quota-created.json

	ACCESS_REQUEST_NAME="Something temporary"
	MP_PRODUCT_ID="pdt-1"
	MP_PRODUCT_VERSION_ID="pdt-v-1"
	MP_ASSETRESOURCE_ID="ares-1"
	MP_SUBSCRIPTION_ID="sub-1"
	jq -n -f ../jq/product-mp-accessrequest.jq --arg accessRequestTile "$ACCESS_REQUEST_NAME" --arg productId $MP_PRODUCT_ID --arg productIdVersion $MP_PRODUCT_VERSION_ID --arg assetResourceId $MP_ASSETRESOURCE_ID --arg subscriptionId $MP_SUBSCRIPTION_ID > ./product-application-access.json
	cat ./product-application-access.json


# Removing icon test
	# create the files
	jq -n -f ../jq/icon.jq --arg icon "MyImageDataHere" > $TEMP_DIR/icon.json
	jq -n -f ../jq/asset-create.jq --arg title "MyTitle" --arg description "MyDescription" --arg icon "MyIconValue" > $TEMP_DIR/asset-create.json
	cat $TEMP_DIR/asset-create.json

	cat $TEMP_DIR/asset-create.json | jq 'del(.icon)' > $TEMP_DIR/asset-create2.json
	cat $TEMP_DIR/asset-create2.json
}

function testReadMarketplaceUrlFromMarketplaceName {

	loginToPlatform

	echo "Lookig for: $MARKETPLACE_TITLE"

	MP_URL=$(readMarketplaceUrlFromMarketplaceName)
	echo "Found MP url: $MP_URL"

	MP_GUID=$(readMarketplaceGuidFromMarketplaceName)
	echo "Found MP guid: $MP_GUID"
}

function testGetCentralUrl {

	loginToPlatform

	echo "Before=$CENTRAL_URL"
	CENTRAL_URL=$(getCentralURL)
	echo "Found Central url: $CENTRAL_URL"

	CENTRAL_URL=$(getCentralURL)
	echo "2nd try check: $CENTRAL_URL"
}


function testDescriptionLength {

	CATALOG_DESCRIPTION=`cat $TEMP_DIR/catalogItem2.json | jq -r ".description"`
	echo "1: $CATALOG_DESCRIPTION"

	sed 's/\\n/\'$'\n''/g' <<< $CATALOG_DESCRIPTION > $TEMP_DIR/catalogItemDescriptionCleaned.txt
	CATALOG_DESCRIPTION=`cat $TEMP_DIR/catalogItemDescriptionCleaned.txt`

	echo "2: $CATALOG_DESCRIPTION"

}

##########################
####### START HERE #######
##########################

#if [[ $# == 0 ]]
#then
#	echo "no parameter"
#else
#	echo "Paramter; $1"
#fi

testDescriptionLength
#testReadingCatalogDocumentation
#testReadingCatalogSubscription
#testCURL
#testOwner
#testNoOwner
#testParameter
#testJQ
#testMarketplaceAPIs
#testErrorFucntion
#testGetApiServiceInstanceOrdered
#sanitizeParenthesisAndSpace "nty (v7-emt)"
#testGetCentralUrl
#findCatalogItemFromConsumerInstance
#testReadMarketplaceUrlFromMarketplaceName

#migrate $PLATFORM_ORGID $PLATFORM_TOKEN $STAGE_NAME "spacex"
#migrate $PLATFORM_ORGID $PLATFORM_TOKEN $STAGE_NAME "nytimes (v7-emt)"
#migrate $PLATFORM_ORGID $PLATFORM_TOKEN $STAGE_NAME "calculatrice (Stage: Demo)"
#migrate $PLATFORM_ORGID $PLATFORM_TOKEN $STAGE_NAME "Recurly"
#migrate $PLATFORM_ORGID $PLATFORM_TOKEN $STAGE_NAME "Bricks"

 