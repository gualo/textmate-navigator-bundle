#Navigator
---

You can [test link](#cgi_exp).

##Release Notes for version 1.0a1
This is the first release of my Navigator system for TextMate.  
This is also my first shot at a Ruby program longer than scripts a few lines long, so if you go into the sources please bear with me, there are certainly better ways/idioms to do things in Ruby. That being said, I'm open to criticism, advice and generally whatever may improve my knowledge of Ruby or programming in general for that matter.

##Introduction

<b>Why Navigator?</b>  
I often need to work on projects with large source bases as well as external source libraries. Navigating in 'foreign' code or even my own code can often become a PITA so I needed a simple yet powerful tool to do it, thus Navigator.

Most features of Navigator should be self explanatory but this document is still a recommended reading.

<b>What it provides</b>  
The Navigator bundle for TextMate provides four tools to help you navigate among your documents:

* A <a href='javascript:goTo("stack")'>position stack</a> tool
* A named or timestamped persistent <a href='javascript:goTo("bookmarks")'>bookmarks</a> tool that works across documents
* A source code <a href='javascript:goTo("tags")'>tagging and lookup</a> tool
* An <a href='javascript:goTo("notes")'>annotations</a> tool

---

---
<p id="stack"></p>
##The Position Stack
The position stack's basic functionality is to allow you to "push onto a stack" the current cursor position so that you can come back to it later. Every time you push a position a new entry is added to the top of the position's stack. You can then "pop" to the last position or navigate among them backwards and forward.  

The saved positions include the document's file so you may navigate among multiple documents easily. Don't worry, even if the new position is in a document that is not currently opened in TextMate, Navigator will open it again before positioning the cursor.

<table cellpadding="0" cellspacing="0" width="80%" style="margin-left:auto; margin-right:auto">
	<tr><td valign="top" style='background-color:lightgray; text-align:justify;'><span style="color:red">Note:&nbsp;&nbsp;</span></td>
		<td style='background-color:lightgray; text-align:justify;valign:top'>as you edit your documents they will become out of sync with the saved positions as line numbers shift.<br/>
There is an <a href="javascript:goTo('stack_exp')">experimental feature</a>, disabled by default, that allows for compensating this line shifting.
	</td></tr>
</table>

### Commands
The position stack tool provides the following commands:
<p id="push_pos"></p>
#### **Push Position**  
Pushes the current cursor position onto the stack
<p id="pop_pos"></p>
#### **Pop Position**  
When you want to go back to the last pushed position you just "pop" the position from the stack. Navigator will then navigate back to it removing it at the same time. When used together with the <a href='javascript:goTo("tags")'>tagging and lookup</a> tool this is similar to a "call/return" action.  
#### **Go Backward / Go Forward**
When you have pushed a few positions onto the stack you may navigate backwards and forward within it as you would do with the "go back/go forward" functionality in a Web browser.  
Navigating forward when you are at the top of the stack will wrap around and bring you to the beginning of it (a tooltip will inform you of this). Likewise, navigating backwards from the beginning of the stack will wrap around to the top of it, i.e. the last pushed position.
#### **Return to Top**
If you have navigated away from the last pushed position either manually or by using the go backward/forward commands to a position somewhere in your documents this command navigates directly to the top position on the stack.
#### **Clear Navigation History**
At any time you may clear the navigation history so you can start a new fresh navigation sequence.

### Behind the scenes
The position's stack is saved to a file located in the temporary directory as given by the *TMPDIR* environment variable, by default named `navstack.nav`. This file is not removed when exiting TextMate adding the extra benefit that if you reopen TextMate your previous positions stack may still be there and active, so you may resume your navigation sequence, for instance by using the "Return to Top" command.

<p id='stack_exp'></p>
### Experimental line shift fix functionality
This is an experimental feature, disabled by default, that allows for compensating the line shifting when editing the documents.  
I call it experimental because it does not always succeed :p and also because it uses the TM\_TOOLS plugin (http://blog.macromates.com/2007/hacking-textmate) which must be installed in order for this feature to work.  

In order to use it you must have TM\_TOOLS installed and have changed the value for the *TM\_NAVIGATOR\_SMART\_POSITIONING* environment variable from 0 to 1. This variable may be modified in the *Settings* preferences section of the Navigator bundle.

---

---
<p id="bookmarks"></p>
##Named Bookmarks
The named bookmarks tool allows you to set named bookmarks in your documents.  
The bookmarks are managed in either the global or project scopes.

<table cellpadding="0" cellspacing="0" width="80%" style="margin-left:auto; margin-right:auto">
<tr><td valign="top" style='background-color:lightgray; text-align:justify;'><span style="color:red">Note:&nbsp;&nbsp;</span></td>
	<td style='background-color:lightgray; text-align:justify;valign:top'>as you edit your documents they will become out of sync with the saved bookmark positions as line numbers shift.<br/>
Use the <a href='javascript:goTo("update_bms");'>Update XXX Bookmarks</a> commands described below to refresh the bookmarks' line numbers.
</td></tr>
</table>

### Commands
The bookmarks tool provides the following commands:
#### *Set Project/Global Bookmark*
This commands allows you to add a new bookmark at the current line position in the current document. The bookmarks is set for either the *Project* or *Global* scopes depending on the command.  
Navigator will prompt you for the bookmark's name which may be anything you like. If you leave the name empty then Navigator will generate a name using the current timestamp.  
If you provide the name of an existing bookmark in the scope then Navigator will update that bookmark's position to the current document's cursor position.

#### *Remove Project/Global/Document Bookmark*
These commands allow you to remove a previously saved bookmark in the scope. A menu appears from which to select the bookmark to be removed.

#### *Goto Project/Global/Document Bookmark*
These commands allow you to navigate to a previously saved bookmark. Navigator will prompt you with a menu displaying the currently saved bookmarks for the scope.  

If using the Document scope then if the document is part of a project Navigator will use the project scope bookmarks for the document, otherwise it uses the global scope bookmarks.

#### *Call Project/Global/Document Bookmark*
These commands behave the same as their "Goto" counterparts but before navigating to the selected bookmark they <a href='javascript:goTo("push_pos");'>push</a> the current cursor position so that you can <a href='javascript:goTo("pop_pos");'>pop</a> back to it later.  

If using the Document scope then if the document is part of a project Navigator will use the project scope bookmarks for the document, otherwise it uses the global scope bookmarks.  

#### *Browse Project/Global Bookmarks*
These commands allow you to browse the currently saved bookmarks in the scope. A fancy browsing window is displayed which should be easy to use. Each entry can be clicked to jump to that line in that file.  
The window allows for filtering the listed bookmarks by name, which may be a regular expression (no need to enclose it in '/'s) and by scope filters: Project or Global.  
The save options button will save the current scope filter settings for use the next time yo open the browsing window. These settings are stored in a file named as the bookmarks files suffixed by *.plist* in the same location as the global bookmarks. This is an experimental feature explained below in the <a href="javascript:goTo('cgi_exp')">CGI Back Call</a> section at the end of this document. 

<p id="update_bms"></p>
#### *Update Project/Global/Document Bookmarks*
As you edit your documents they will become out of sync with the saved bookmark positions as line numbers shift.
These commands "try" to fix this by scanning the bookmarks' documents for their associated line contents for the one nearest the current bookmarks positions. Also, if a bookmark's document doesn't exist anymore that bookmark is removed.

#### *Clear Project/Global/Document Bookmarks*
These commands allow you to remove all currently saved bookmarks for the scope.

### Behind the scenes
When you add a new bookmark to the project scope of an active project that bookmark is saved to a project specific bookmarks file located at the project's root directory and named as specified by the *TM\_NAVIGATOR\_BOOKMARKS\_FNAME* environment variable which is *bookmarks.nav* by default. This variable may be modified in the *Settings* preferences section of the Navigator bundle.

Bookmarks added to the global scope are saved to the equally named file located in the directory specified in the *TM\_NAVIGATOR\_BOOKMARKS\_PATH*. This variable may also be modified in the *Settings* preferences section of the Navigator bundle.  
The specified global bookmark's path may be either absolute or relative.  
If absolute (i.e. begins with a '/') then that path is used "as is".   
If on the other hand the path is relative (i.e. does not begin with a '/') then that path is appended to the current user's *HOME* directory.

---

---
<p id="tags"></p>
## *Tags and Lookup*
The tags and lookup tool provides for source tagging and lookup when working with a project.  
Source parsing and tagging is done using the underlying Exuberant Ctags program (Version 5.8 which includes experimental support for Objective-C) so it will parse any language known to it.  
<table cellpadding="0" cellspacing="0" width="80%" style="margin-left:auto; margin-right:auto">
	<tr><td valign="top" style='background-color:lightgray; text-align:justify;'><span style="color:red">Note:&nbsp;&nbsp;</span></td>
	<td style='background-color:lightgray; text-align:justify;valign:top'>as you edit your documents they will become out of sync with the saved positions as line numbers shift.<br/>
There is an <a href="javascript:goTo('stack_exp')">experimental feature</a>, disabled by default, that allows for compensating this line shifting.
</td></tr>
</table>
  
### Commands
The tags tool provides the following commands:

#### *Call Context Tag*
This command will use the current context under the cursor to find a matching tagged identifier. The context may be either a text selection or the current word as recognized by TextMate.  

If an unique tag is found then Navigator will <a href='javascript:goTo("push_pos");'>push</a> the current cursor position and navigate to the tag file and position.    

If more than one tag is found then a menu will be displayed allowing you to choose the one you want to "call".  
The selected tags are displayed in up to four groups in this order:

 - the matching tags in the currently edited file (prefixed with "F")
 - the matching tags in files within the current project (prefixed with "P")
 - the matching tags in files within the current project's extra paths (prefixed with "X")
 - all the other global matching tags (prefixed with "G")

Tags within the same group are sorted by the tag's identifier, then by their path and finally by their tag's line number

When more than one tag matches Navigator tries to narrow the selection to a single "perfect" match, and if found then automatically selects it.  
This is controlled by the *TM\_NAVIGATOR\_SMART\_LOOKUP* environment variable in the *Settings* preferences section of the Navigator bundle. Set to 1 to activate the lookup optimization, set to 0 to always display all the matching tags.

#### *Goto Context Tag*
This command behaves the same as its "Call" counterpart but only navigates to the selected tag without saving the current position.

#### *Call User Tag*
This command behaves the same as its "Context" counterpart but instead of using the context it prompts the user for a lookup expression.  
This expression maybe:

 - *a simple string* : in which case any tag containing the string anywhere matches.  
For instance the string "init" will match "<span style="background-color:yellow;">init</span>ialize" as well as "resource\_<span style="background-color:yellow;">init</span>\_from\_file"  

 - *a regular expression* : delimited by '/' in which you specify what you are looking for.  
For instance to select all tags of event handlers you could provide "/^on\_.*/" which will match "<span style="background-color:yellow;">on\_</span>load", "<span style="background-color:yellow;">on\_</span>command\_print" and so on, but not "remove\_on\_condition".  

I use this command also to explore the Ruby standard library for sample code. For example by providing "each" I can navigate through all the implementations of the "each" method to see how "they" do things 8-)

#### *Goto User Tag*
This command behaves the same as its "Call" counterpart but only navigates to the selected tag without saving the current position.

#### *Refresh Current File Tags*
This is a very fast and unobtrusive operation that tags only the currently edited file.

#### *Refresh Selected Files Tags*
Refreshes the tags of the files selected in the project panel.

#### *Refresh Project Tags*
Tags all the project's files.  
The project files are those in the directory tree based at the project's directory as well as any paths specified by the <u>project specific</u> environment variable *TM\_NAVIGATOR\_PROJECT\_TAGS\_PATH*.  
This variable may contain a list of ':' separated paths to include in the scan.  
This may be used for instance to include project related libraries or projects outside of the current project's directory.  

When selecting files for tagging Navigator will ignore files whose full path matches the regular expression specified in the environment variable *TM\_NAVIGATOR\_TAGS\_IGNORE*. It may be modified in the *Settings* preferences section of the Navigator bundle. 

#### *Update Project Tags*
Refreshes the tags of only the files in the current project that have changed since the last full project scan.

#### *Refresh All Tags*
This command tags all the project files as well as paths specified by the environment variable *TM\_NAVIGATOR\_GLOBAL\_TAG\_PATH*. It may be modified in the *Settings* preferences section of the Navigator bundle.  
This variable may contain a list of ':' separated paths to include in the scan.  
This may be used for instance to include standard libraries or projects outside of the project's directory that <u>seldom change</u>.

#### *Show Last Scan Date*
Displays the last time a full project scan was performed

### Behind the scenes
By default Navigator automatically sets the 'm' file extension to the files tagged as Objective-C. You may specify a different list using the <u>project specific</u> environment variable *TM\_NAVIGATOR\_FORCE\_OBJC*. This variable should contain a ':' separated list of case insensitive extensions, without the dots, as in **m:h**

A project's tags are saved in the project's directory to a file named as specified by the environment variable *TM\_NAVIGATOR\_TAGS\_FNAME*, by default ***.tags.nav***, a hidden file. You may change it in the *Settings* preferences section of the Navigator bundle.  

Global tags are saved to the equally named file located in the directory specified in the *TM\_NAVIGATOR\_GLOBAL\_TAG\_FILE\_PATH*. This variable may also be modified in the *Settings* preferences section of the Navigator bundle.  
The specified global tags path may be either absolute or relative.  
If absolute (i.e. begins with a '/') then that path is used "as is".   
If on the other hand the path is relative (i.e. does not begin with a '/') then that path is appended to the current user's *HOME* directory.

A secondary helper file is also stored in the project's directory named as the tags file suffixed by ".plist" (i.e. ***.tags.plist*** by default). This file is used to store state information about the tagging, like for instance the last time a full project scan was performed.

---

---
<p id="notes"></p>
##Annotations tool
The annotations tool allows you to easily navigate among your <u>project</u> documents annotations.  
Annotations are text lines containing tags that determine their type or intent.  
Examples of annotations are:

	# TODO: check that the resource is available
	# FIX ME: crash when list is empty
	or
	# DOC: Explain the usage of TM\_NAVIGATOR\_FORCE\_OBJC in the user manual

Navigator comes preconfigured with a number of tags. You may add change or remove tags as described in the <a href='javascript:goTo("notes_tech")'>Behind the Scenes</a> at the end of this section.  

The preconfigured tags are:

 - FIXME
 - TODO
 - NOTE
 - CHANGED
 - DOC

### Commands
The annotations tool provides the following commands:

#### *Browse Project Annotations*
This command allows you to browse the currently saved annotations. A fancy browsing window is displayed which should be easy to use. Each entry can be clicked to jump to that line in that file.

#### *Goto Annotation*
This command will prompt you with a menu listing all the known annotations in your project. When you select an annotation Navigator will navigate to its file and position.

#### *Goto Document Annotation*
This command behaves the same as "Goto Note" but filters the annotation to the ones in the currently edited document.

#### *Goto Annotation of Type*
Navigator will prompt you with a menu listing the defined annotation types. After you select a type Navigator will proceed as for the "Goto Note" command but filtering the annotations to those of the selected type.

#### *Refresh Current File Annotations*
Scans the current file and updates its annotations. Remember to save any files before invoking these commands.

#### *Refresh Selected Files Annotations*
Scans the files selected in the project panel and updates their annotations.

#### *Refresh Project Annotations*
Scans all the project's files and updates their annotations.  
The project files are those in the directory tree based at the project's directory as well as any paths specified by the <u>project specific</u> environment variable *TM\_NAVIGATOR\_PROJECT\_EXTRA\_NOTE\_PATH*.  
This variable may contain a list of ':' separated paths to include in the scan.  
This may be used for instance to include project related libraries or projects outside of the project's directory.  

When selecting files for scanning Navigator will ignore files whose full path matches the regular expression specified in the environment variable *TM\_NAVIGATOR\_NOTES\_IGNORE*. It may be modified in the *Settings* preferences section of the Navigator bundle. 

### Behind the scenes
A project's notes are saved in the project's directory to a file named as specified by the environment variable *TM\_NAVIGATOR\_NOTES\_FNAME*, by default ***.notes.nav***, a hidden file. You may change it in the *Settings* preferences section of the Navigator bundle.  



 in the *Note Settings* preferences of the Navigator bundle.  
For each tag type you define you must provide a regular expression that matches the lines containing the tag. This regular expression must yield two groups, the first containing the tag text, and the second containing the text of the note (limited to the end of the line).  
Note that the matching is case insensitive.  

---

---

<a name="cgi_exp">
<p id="cgi_exp"></p>
## CGI Callback
The CGI callback feature is an experiment in mixing HTML/Javascript for UI design and Ruby for the "back-office" processing in TextMate.  



---

---
<p id="history"></p>
#History

(1-9-12)
First release

<script type="text/javascript" charset="utf-8">
function goTo (id) {
  document.body.scrollTop = document.getElementById(id).offsetTop - document.images[0].height - 1;
}
</script>
