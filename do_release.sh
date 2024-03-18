#!/bin/bash

[ -n "$DEBUG" ] && [[ $(echo "$DEBUG" | tr '[:upper:]' '[:lower:]') =~ ^y|yes|1|on$ ]] && \
        set -xe || set -e


function do_release() {
	echo "Making release"
		
	#find version:
	VERSION=$(grep -e "^VERSION.*--PKG_VERSION_MARK--.*$" src/nftlist.sh | sed 's/\(^VERSION\s*=\s*\)\(.*\)\(\#.*$\)/\2/' | tr -d '"' | tr -d "'" | xargs)
	
	if [ -z $VERSION ] || ! [[ "$VERSION" =~ ^[a-z|0-9|\.|\-]{3,32}$ ]]; then
		echo "No version has been found, or incorrect version format"
		exit 1
	fi
	
	RELEASE_NAME=nfthelper-$VERSION
	RELEASE_PATH=./release/$RELEASE_NAME.tar.gz

	if [ ! -d "release" ]; then 
		mkdir release
	fi
	
	if [ -f $RELEASE_PATH ]; then 
		echo "File '$RELEASE_PATH' already exists, no thing to do, exiting"
		exit 0
	fi

	#tar --transform "s/^src/$RELEASE_NAME/" -czf $RELEASE_PATH src
	tar --transform "s/^src\/nft-helper.sh/usr\/local\/bin\/nftlist.sh/" \
		--transform "s/^src\/nft-helper/etc\/init.d\/nftlist/" \
		-czf $RELEASE_PATH src/nftlist.sh src/nftlist
	
	echo "File prepared: $RELEASE_PATH"
}



function do_info() {
	echo "For implementation"
}

case "$1" in 
	"release")
		do_release
		;;
	
	"help"|"-h"|"-help"|"--help")
		do_info
		;;
	*)
		
		;;
esac

exit 0
