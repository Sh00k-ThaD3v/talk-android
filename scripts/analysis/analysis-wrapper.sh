#!/usr/bin/env bash

#1: GIT_USERNAME
#2: GIT_TOKEN
#3: BRANCH
#4: LOG_USERNAME
#5: LOG_PASSWORD
#6: DRONE_BUILD_NUMBER
#7: PULL_REQUEST_NUMBER


repository="talk"

if [[ $3 = \stable-* ]] ; then
  stableBranch=$3
else
  stableBranch="master"
fi

ruby scripts/analysis/lint-up.rb $1 $2 $3
lintValue=$?

ruby scripts/analysis/findbugs-up.rb $1 $2 $3
findbugsValue=$?

# exit codes:
# 0: count was reduced
# 1: count was increased
# 2: count stayed the same

echo "Branch: $3"

if [ $3 = $stableBranch ]; then
    echo "New findbugs result for $stableBranch at: https://www.kaminsky.me/nc-dev/$repository-findbugs/$stableBranch.html"
    curl -k -u $4:$5 -X PUT https://nextcloud.kaminsky.me/remote.php/webdav/$repository-findbugs/$stableBranch.html --upload-file app/build/reports/spotbugs/spotbugs.html

    summary=$(sed -n "/<h1>Summary<\/h1>/,/<h1>Warnings<\/h1>/p" app/build/reports/spotbugs/spotbugs.html | head -n-1 | sed s'/<\/a>//'g | sed s'/<a.*>//'g | sed s"/Summary/SpotBugs ($stableBranch)/" | tr "\"" "\'" | tr -d "\r\n")
    curl -k -u $4:$5 -X PUT -d "$summary" https://nextcloud.kaminsky.me/remote.php/webdav/$repository-findbugs/findbugs-summary-$stableBranch.html

    if [ $lintValue -ne 1 ]; then
        echo "New lint result for $stableBranch at: https://www.kaminsky.me/nc-dev/$repository-lint/$stableBranch.html"
        curl -k -u $4:$5 -X PUT https://nextcloud.kaminsky.me/remote.php/webdav/$repository-lint/$stableBranch.html --upload-file app/build/reports/lint/lint.html
        exit 0
    fi
else
    if [ -e $6 ]; then
        6=$stableBranch"-"$(date +%F)
    fi
    echo "New lint results at https://www.kaminsky.me/nc-dev/$repository-lint/$6.html"
    curl -k -u $4:$5 -X PUT https://nextcloud.kaminsky.me/remote.php/webdav/$repository-lint/$6.html --upload-file app/build/reports/lint/lint.html

    echo "New findbugs results at https://www.kaminsky.me/nc-dev/$repository-findbugs/$6.html"
    curl -k -u $4:$5 -X PUT https://nextcloud.kaminsky.me/remote.php/webdav/$repository-findbugs/$6.html --upload-file app/build/reports/spotbugs/spotbugs.html

    # delete all old comments
    oldComments=$(curl -k 2>/dev/null -u $1:$2 -X GET https://api.github.com/repos/nextcloud/talk-android/issues/$7/comments | jq '.[] | (.id |tostring) + "|" + (.user.login | test("nextcloud-android-bot") | tostring) ' | grep true | tr -d "\"" | cut -f1 -d"|")

    echo $oldComments | while read comment ; do
        curl -k 2>/dev/null -u $1:$2 -X DELETE https://api.github.com/repos/nextcloud/talk-android/issues/comments/$comment
    done

    # lint and findbugs file must exist
    if [ ! -s app/build/reports/lint/lint.html ] ; then
        echo "lint.html file is missing!"
        exit 1
    fi

    if [ ! -s app/build/reports/spotbugs/spotbugs.html ] ; then
        echo "spotbugs.html file is missing!"
        exit 1
    fi

    # add comment with results
    lintResultNew=$(grep "Lint Report.* [0-9]* warning" app/build/reports/lint/lint.html | cut -f2 -d':' |cut -f1 -d'<')

    lintErrorNew=$(echo $lintResultNew | grep "[0-9]* error" -o | cut -f1 -d" ")
    if ( [ -z $lintErrorNew ] ); then
        lintErrorNew=0
    fi

    lintWarningNew=$(echo $lintResultNew | grep "[0-9]* warning" -o | cut -f1 -d" ")
    if ( [ -z $lintWarningNew ] ); then
        lintWarningNew=0
    fi

    lintResultOld=$(curl -k 2>/dev/null https://raw.githubusercontent.com/nextcloud/talk-android/$stableBranch/scripts/analysis/lint-results.txt)
    lintErrorOld=$(echo $lintResultOld | grep "[0-9]* error" -o | cut -f1 -d" ")
    if ( [ -z $lintErrorOld ] ); then
        lintErrorOld=0
    fi

    lintWarningOld=$(echo $lintResultOld | grep "[0-9]* warning" -o | cut -f1 -d" ")
    if ( [ -z $lintWarningOld ] ); then
        lintWarningOld=0
    fi

    lintResult="<h1>Lint</h1><table width='500' cellpadding='5' cellspacing='2'><tr class='tablerow0'><td>Type</td><td><a href='https://www.kaminsky.me/nc-dev/"$repository"-lint/"$stableBranch".html'>$stableBranch</a></td><td><a href='https://www.kaminsky.me/nc-dev/"$repository"-lint/"$6".html'>PR</a></td></tr><tr class='tablerow1'><td>Warnings</td><td>"$lintWarningOld"</td><td>"$lintWarningNew"</td></tr><tr class='tablerow0'><td>Errors</td><td>"$lintErrorOld"</td><td>"$lintErrorNew"</td></tr></table>"
    findbugsResultNew=$(sed -n "/<h1>Summary<\/h1>/,/<h1>Warnings<\/h1>/p" app/build/reports/spotbugs/spotbugs.html |head -n-1 | sed s'/<\/a>//'g | sed s'/<a.*>//'g | sed s"#Summary#<a href=\"https://www.kaminsky.me/nc-dev/$repository-findbugs/$6.html\">SpotBugs</a> (new)#" | tr "\"" "\'" | tr -d "\n")
    findbugsResultOld=$(curl -k 2>/dev/null https://www.kaminsky.me/nc-dev/$repository-findbugs/findbugs-summary-$stableBranch.html | tr "\"" "\'" | tr -d "\r\n" | sed s"#SpotBugs#<a href=\"https://www.kaminsky.me/nc-dev/$repository-findbugs/$stableBranch.html\">SpotBugs</a>#" | tr "\"" "\'" | tr -d "\n")


    if ( [ $lintValue -eq 1 ] ) ; then
        lintMessage="<h1>Lint increased!</h1>"
    fi

    if ( [ $findbugsValue -eq 1 ] ) ; then
        findbugsMessage="<h1>SpotBugs increased!</h1>"
    fi

    # check for NotNull
    if [[ $(grep org.jetbrains.annotations src/main/* -ir -c) -gt 0 ]] ; then
        notNull="org.jetbrains.annotations.NotNull is used. Please use androidx.annotation.NonNull instead.<br><br>"
    fi

    curl -k -u $1:$2 -X POST https://api.github.com/repos/nextcloud/talk-android/issues/$7/comments -d "{ \"body\" : \"$lintResult $findbugsResultNew $findbugsResultOld $lintMessage $findbugsMessage $notNull\" }"

    if [ ! $lintValue -eq 2 ]; then
        exit $lintValue
    fi

    if [[ -n $notNull ]]; then
        exit 1
    fi

    if [ $findbugsValue -eq 2 ]; then
        exit 0
    else
        exit $findbugsValue
    fi
fi
