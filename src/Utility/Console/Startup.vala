
using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.System;
using TeeJee.ProcessHelper;

public class StartupEntry: GLib.Object{

	public string STARTUP_SCRIPT_FILE = "";
	public string STARTUP_DESKTOP_FILE = "";
	public int startup_delay = 10;
	public string user_name = "";
	public string user_home = "";
	public string app_name = "";
	public string entry_name = "";
	
	public StartupEntry(string _user_name, string _app_name, string _entry_name, int startup_delay_secs){
		
		user_name = _user_name;
		user_home = get_user_home(user_name);
		app_name = _app_name;
		entry_name = _entry_name;
		startup_delay = startup_delay_secs;
		
		STARTUP_SCRIPT_FILE = "%s/.config/%s/%s.sh".printf(user_home, app_name, entry_name);
		STARTUP_DESKTOP_FILE = "%s/.config/autostart/%s_%s.desktop".printf(user_home, app_name, entry_name);
	}
	
	public string create(string command, bool give_ownership){

		if (file_exists(STARTUP_SCRIPT_FILE)){
			file_delete(STARTUP_SCRIPT_FILE);
		}
		
		string txt = "";
		txt += "sleep %ds\n".printf(startup_delay);
		txt += "%s \n".printf(command);

		dir_create(file_parent(STARTUP_SCRIPT_FILE));
		file_write(STARTUP_SCRIPT_FILE, txt);

		create_startup_desktop_file();

		if (give_ownership){
			set_owner();
		}

		return STARTUP_DESKTOP_FILE;
	}

	public void set_owner(){

		chown(file_parent(STARTUP_SCRIPT_FILE), user_name, user_name);
		chown(STARTUP_SCRIPT_FILE, user_name, user_name);
		chown(STARTUP_DESKTOP_FILE, user_name, user_name);
	}

	private void create_startup_desktop_file(){

		if (file_exists(STARTUP_DESKTOP_FILE)){
			file_delete(STARTUP_DESKTOP_FILE);
		}
		
		string txt =
"""[Desktop Entry]
Type=Application
Exec={command}
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Name[en_IN]=Ukuu Notification
Name=Ukuu Notification
Comment[en_IN]=Ukuu Notification
Comment=Ukuu Notification
""";

		txt = txt.replace("{command}", "sh \"%s\"".printf(STARTUP_SCRIPT_FILE));

		file_write(STARTUP_DESKTOP_FILE, txt);

		chown(STARTUP_DESKTOP_FILE, user_name, user_name);
	}

	public void remove(){
		if (file_exists(STARTUP_SCRIPT_FILE)){
			file_delete(STARTUP_SCRIPT_FILE);
		}
		if (file_exists(STARTUP_DESKTOP_FILE)){
			file_delete(STARTUP_DESKTOP_FILE);
		}
	}

}
