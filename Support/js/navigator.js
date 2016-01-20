//
// Creates a 'ruby' compatible script for use with the callScript command
// The script parameter contains a string with newlines for each command
function makeRubyScript(aScript) {
	lines = aScript.split("\n");
	// We use the ruby18 supplied by TM for compatibility reasons
	ruby_program = ENV["TM_SUPPORT_PATH"] + "/bin/ruby18"
	ruby_program = ruby_program.replace(/ /g, "\\ ")
    command = ruby_program + " -e \'\' \\\n";
	for (line in lines) {
		command = command + '-e \''+ lines[line] +'\' \\\n';
	}
	command = command + '\n';
	
	return command;
};

//
// Creates a 'ruby' TextMate compatible script for use with the callTMScript comand
// The script parameter contains a string with newlines for each command
function makeTMRubyScript(aScript) {
	lines = aScript.split("\n");
    command = '';
	for (line in lines) {
		command = command + lines[line] +'\\\n';
	}
	command = command + '\n';
	
	return command;
};

// executes a command
function callScript(command, handler) {
	if (handler) {
		process = TextMate.system(command, handler);
		return process;
	}
	else {
		process = TextMate.system(command, null);
		return process;
	}
};

// executes a Ruby script
function callRubyScript(command, handler) {
	command = makeRubyScript(command);
	console.log("<pre>"+command+"</pre>");
	return callScript(command, handler);
};

// executes a TextMate script using TMTOOLS
function callTMScript(cmd, handler, path, line, column, input, output, before_running) {
	console.log("cmd, path, line, column, input, output, before_running=\n"+cmd+"\n"+path+"\n"+line+"\n"+column+"\n"+input+"\n"+output+"\n"+before_running);
  command = '<dict>\n\
<key>beforeRunningCommand</key>\n\
<string>'+(before_running==null?"nop":before_running)+'</string>\n\
<key>command</key>\n\
<string>'+cmd+'</string>\n\
<key>input</key>\n\
<string>'+(input==null?"none":input)+'</string>\n\
<key>output</key>\n\
<string>'+(output==null?"discard":output)+'</string>\n\
</dict>\n\
';

	if (path) {
		command = 'open "txmt://open?url=file://'+escape(path)+''+(line!=null?"&line="+line:"")+(column!=null?"&column="+column:"")+'";"' + ENV["TMTOOLS"] + '" call command  \'' + command + '\'';
	}
	else {
		command = 'open "txmt://open?";"$TMTOOLS" call command  \'' + command + '\'';
	}
	console.log("Final script\n" + command);
	if (handler) {
		process = TextMate.system(command, handler);
		return process;
	}
	else {
		process = TextMate.system(command, null);
		console.log("Execution result status="+process.status+" output=\n" +process.outputString+"errors="+process.errorString);
		return [process.status, process.outputString, command, process];
	}
};

// executes a TextMate command using TMTOOLS
function callTMCommand(cmd, handler) {
	var command = 'open "txmt://open?";"$TMTOOLS" call command  "{name=\'' + cmd + '\';}"';
	if (handler) {
		process = TextMate.system(command, handler);
		return process;
	}
	else {
		process = TextMate.system(command);
		return [process.status, process.outputString, command];
	}
};

function folderSelect(prompt, initialPath) {
	theScript = 'osascript <<AS \n' +
		'tell app "Finder"\n' +
			'activate\n' +
			'set theFolder to choose folder';
	if (prompt) {
		theScript += ' with prompt "' + prompt + '"';
	}
	if (initialPath) {
		theScript += ' default location "' + initialPath + '"';
	}
	theScript += '\nend tell\n' +
		'POSIX path of theFolder as string \n' +
		'AS';
	
	selectedFolder = trim(callScript(theScript).outputString);
	// remove trailing '/'
	while(selectedFolder.charAt( selectedFolder.length-1 ) == "/") {
	    selectedFolder = selectedFolder.slice(0, -1);
	}

	// return focus to TM
	// TODO: returning focus to TM causes a freeze!!
	// activateTextMate();

	return selectedFolder;
};

function activateApplication(appName) {
	cmd = "/usr/bin/osascript -e 'tell app \"" + appName + "\"' -e 'activate' -e 'end tell'"
	return callScript(cmd);
};

function activateTextMate() {
	return activateApplication("TextMate");
};

// TODO: Change to use direct scripting instead of going through goto_file.sh
function gotoFile(path, lookupExpression, line, column) {
	gotoFileNew(path, lookupExpression, line, column);
	// console.log("<pre>"+ENV["TM_BUNDLE_SUPPORT"]+"</pre>");
	// command = '"'+ENV["TM_BUNDLE_SUPPORT"]+'/bin/goto_file.sh"';
	// command = command + ' "'+escape(path)+'"';
	// command = command + ' "'+path+'"';
	// command = command + ' "'+lookupExpression+'"';
	// command = command + ' "'+ENV["TM_BUNDLE_SUPPORT"]+'"';
	// command = command + ' "'+ENV["TM_PROJECT_DIRECTORY"]+'"';
	// command = command + ' "'+ENV["TM_SUPPORT_PATH"]+'"';
	// command = command + ' "'+ENV["TM_NAVIGATOR_MAX_DELTA_LINES"]+'"';
	// command = command + ' "'+ENV["TMTOOLS"]+'"';
	// command = command + ' '+line;
	// command = command + ' '+column;
	// console.log("Final command\n"+command);
	// 
	// process = callScript(command, null);
	// console.log("Execution result status="+process.status+" output=\n" +process.outputString+"errors="+process.errorString);
};

// TODO: Test change to use direct scripting instead of going through goto_file.sh
function gotoFileNew(path, lookupExpression, line, column)
{
	command = '\
ENV["TM_BUNDLE_SUPPORT"] 		= "' + ENV["TM_BUNDLE_SUPPORT"] 		+ '";\
ENV["TM_PROJECT_DIRECTORY"] = "' + ENV["TM_PROJECT_DIRECTORY"] 	+ '";\
ENV["TM_SUPPORT_PATH"] 		= "' + ENV["TM_SUPPORT_PATH"] 		+ '";\
require "#{ENV["TM_BUNDLE_SUPPORT"]}/navigator.rb";\
Navigator.goto_file "' + path + '", ' + lookupExpression+', ' + line + ', ' + column + '\n\
';

	console.log("Final command\n"+command);
	callTMScript(command, null, path, line, column, null, "showAsHTML");
	console.log("Execution result status="+process.status+" output=\n" +process.outputString+"errors="+process.errorString);
};


function escapeRegexp(exp) {
    return exp.replace(/([.*+?"'|(){}[\]\\])/g, "\\$&");
}

function escapeEscapes(value) {
	return value.replace(/\\/g, "\\\\");
}

function trim(str) {
	return str.replace(/^\s+|\s+$/g,"");
};

function expandPath(basePath) {
	if (basePath[0] == '~') {
		basePath = ENV['HOME'] + basePath.substring(1);
	}
	envVars = basePath.match(/\$\w+/);
	if (envVars.length > 0) {
		// reorder by longest name length to allow for vars with the same stem
		envVars.sort(function(item1, item2) {return (item2.length-item1.length);});
		for (i = 0; i < envVars.length;i++) {
			varName = envVars[i].substring(1);

			if (ENV[varName]) varValue = ENV[varName];
			else varValue = "";

			basePath.replace(envVars[i], varValue);
		}
	}
	
	return basePath;
}


//////////////////////////////////////////////////////////////////

Tab = function(tabId, firstField) {
	this.tabId = tabId;
	this.firstField = firstField;
};

Tab.prototype.setActive = function(active) {
	elem = document.getElementById(this.tabId + "_title");
	elem.className = active?"tab_tab tab_selected":"tab_tab";
	elem = document.getElementById(this.tabId + "_contents");
	newStyle = active?"content_displayed":"content_hidden";
	elem.className = elem.className.replace(/content_(hidden|displayed)/, newStyle);
	if (active && this.firstField) document.getElementById(this.firstField).focus();
};

Tabs = function() {
	this.tabs = [];
	this.currentTab = "";
};

Tabs.prototype.currentTab = function() {
	return this.currentTab;
};

Tabs.prototype.activate = function (selectedId) {
	for (tabId in this.tabs){
		tab = this.tabs[tabId];
		tab.setActive(tab.tabId == selectedId);
	}
};

Tabs.prototype.addTab = function(tabId, tabFirstField) {
	this.tabs[tabId] = new Tab(tabId, tabFirstField);
	if (this.currentTab == "") this.currentTab = tabId;
};
