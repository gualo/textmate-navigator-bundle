#!/usr/bin/env bash
#
tm_url="$1"
tm_path="$2"
tm_exp="$3"
tm_BUN_PATH="$4"
tm_PROJ_DIR="$5"
tm_SUP_PATH="$6"
tm_NAV_MAX_DELTA="$7"
tm_TMTOOLS="$8"
tm_line="$9"
shift
tm_column="$9"

open "txmt://open?url=file://$tm_url&line=$tm_line&column=$tm_column"

"$TMTOOLS" call command "<dict>
<key>beforeRunningCommand</key>
<string>nop</string>
<key>command</key>
<string>#!/usr/bin/env ruby
ENV[\"TM_BUNDLE_PATH\"] = \"$tm_BUN_PATH\"
ENV[\"TM_PROJECT_DIRECTORY\"] = \"$tm_PROJ_DIR\"
ENV[\"TM_SUPPORT_PATH\"] = \"$tm_SUP_PATH\"
ENV[\"TM_NAVIGATOR_MAX_DELTA_LINES\"] = \"$tm_NAV_MAX_DELTA\"
ENV[\"TMTOOLS\"] = \"$tm_TMTOOLS\"
require \"#{ENV[\"TM_BUNDLE_PATH\"]}/Support/navigator.rb\"
Navigator.goto_file(\"$tm_path\", $tm_exp, $tm_line, $tm_column)
</string>
<key>input</key>
<string>none</string>
<key>output</key>
<string>discard</string>
</dict>
"
status=$?
if [ $status == 0 ]
then
	echo Operation succceeded
	exit 0
else
	echo Operation failed with status $status
	exit $status
fi
