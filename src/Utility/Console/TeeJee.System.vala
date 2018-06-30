
/*
 * TeeJee.System.vala
 *
 * Copyright 2017 Tony George <teejeetech@gmail.com>
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston,
 * MA 02110-1301, USA.
 *
 *
 */
 
namespace TeeJee.System{

	using TeeJee.ProcessHelper;
	using TeeJee.Logging;
	using TeeJee.Misc;
	using TeeJee.FileSystem;
	
	// user ---------------------------------------------------
	
	public bool user_is_admin (){

		/* Check if current application is running with admin priviledges */

		try{
			// create a process
			string[] argv = { "sleep", "10" };
			Pid procId;
			Process.spawn_async(null, argv, null, SpawnFlags.SEARCH_PATH, null, out procId);

			// try changing the priority
			Posix.setpriority (Posix.PRIO_PROCESS, procId, -5);

			// check if priority was changed successfully
			if (Posix.getpriority (Posix.PRIO_PROCESS, procId) == -5)
				return true;
			else
				return false;
		}
		catch (Error e) {
			log_error (e.message);
			return false;
		}
	}

	public int get_user_id(){

		// returns actual user id of current user (even for applications executed with sudo and pkexec)
		
		string pkexec_uid = GLib.Environment.get_variable("PKEXEC_UID");

		if (pkexec_uid != null){
			return int.parse(pkexec_uid);
		}

		string sudo_user = GLib.Environment.get_variable("SUDO_USER");

		if (sudo_user != null){
			return get_user_id_from_username(sudo_user);
		}

		return get_user_id_effective(); // normal user
	}

	public int get_user_id_effective(){
		
		// returns effective user id (0 for applications executed with sudo and pkexec)

		int uid = -1;
		string cmd = "id -u";
		string std_out, std_err;
		exec_sync(cmd, out std_out, out std_err);
		if ((std_out != null) && (std_out.length > 0)){
			uid = int.parse(std_out);
		}

		return uid;
	}
	
	public string get_username(){

		// returns actual username of current user (even for applications executed with sudo and pkexec)
		
		return get_username_from_uid(get_user_id());
	}

	public string get_username_effective(){

		// returns effective user id ('root' for applications executed with sudo and pkexec)
		
		return get_username_from_uid(get_user_id_effective());
	}

	public int get_user_id_from_username(string username){
		
		// check local user accounts in /etc/passwd -------------------

		foreach(var line in file_read("/etc/passwd").split("\n")){
			
			var arr = line.split(":");
			
			if ((arr.length >= 3) && (arr[0] == username)){
				
				return int.parse(arr[2]);
			}
		}

		// check remote user accounts with getent -------------------
			
		var arr = get_user_with_getent(username).split(":");

		if ((arr.length >= 3) && (arr[0] == username)){

			return int.parse(arr[2]);
		}

		// not found --------------------
		
		log_error("UserId not found for userName: %s".printf(username));

		return -1;
	}

	public string get_username_from_uid(int user_id){

		// check local user accounts in /etc/passwd -------------------
		
		foreach(var line in file_read("/etc/passwd").split("\n")){
			
			var arr = line.split(":");
			
			if ((arr.length >= 3) && (arr[2] == user_id.to_string())){
				
				return arr[0];
			}
		}

		// check remote user accounts with getent -------------------
			
		var arr = get_user_with_getent(user_id.to_string()).split(":");

		if ((arr.length >= 3) && (arr[2] == user_id.to_string())){

			return arr[0];
		}

		// not found --------------------
		
		log_error("Username not found for uid: %d".printf(user_id));

		return "";
	}

	public string get_user_home(string username = get_username()){

		// check local user accounts in /etc/passwd -------------------
		
		foreach(var line in file_read("/etc/passwd").split("\n")){
			
			var arr = line.split(":");
			
			if ((arr.length >= 6) && (arr[0] == username)){

				return arr[5];
			}
		}

		// check remote user accounts with getent -------------------
		
		var arr = get_user_with_getent(username).split(":");
		
		if ((arr.length >= 6) && (arr[0] == username)){

			return arr[5];
		}

		// not found --------------------

		log_error("Home directory not found for user: %s".printf(username));

		return "";
	}

	public string get_user_with_getent(string user_name_or_uid){

		string cmd = "getent passwd " + user_name_or_uid;
		string std_out, std_err;
		exec_sync(cmd, out std_out, out std_err);
		return std_out;
	}

	public string get_user_home_effective(){
		return get_user_home(get_username_effective());
	}
	
	// application -----------------------------------------------
	
	public string get_app_path(){

		/* Get path of current process */

		try{
			return GLib.FileUtils.read_link ("/proc/self/exe");
		}
		catch (Error e){
	        log_error (e.message);
	        return "";
	    }
	}

	public string get_app_dir(){

		/* Get parent directory of current process */

		try{
			return (File.new_for_path (GLib.FileUtils.read_link ("/proc/self/exe"))).get_parent ().get_path ();
		}
		catch (Error e){
	        log_error (e.message);
	        return "";
	    }
	}

	// system ------------------------------------

	public Gee.ArrayList<string> list_dir_names(string path){
		
		var list = new Gee.ArrayList<string>();
		
		try
		{
			File f_home = File.new_for_path (path);
			FileEnumerator enumerator = f_home.enumerate_children ("%s".printf(FileAttribute.STANDARD_NAME), 0);
			FileInfo file;
			while ((file = enumerator.next_file ()) != null) {
				string name = file.get_name();
				//string item = path + "/" + name;
				list.add(name);
			}
		}
		catch (Error e) {
			log_error (e.message);
		}

		//sort the list
		CompareDataFunc<string> entry_compare = (a, b) => {
			return strcmp(a,b);
		};
		list.sort((owned) entry_compare);

		return list;
	}

	// internet helpers ----------------------
	
	public bool check_internet_connectivity(){

	    return check_internet_connectivity_wget_google();
	}

	public bool check_internet_connectivity_wget_google(){
		
		int exit_code = -1;
		string std_err;
		string std_out;

		string cmd = "wget -q --tries=10 --timeout=10 --spider http://google.com";
		cmd += " ; exit $?";
		exit_code = exec_script_sync(cmd, out std_out, out std_err, false);

	    return (exit_code == 0);
	}
	
	public bool shutdown (){

		/* Shutdown the system immediately */

		try{
			string[] argv = { "shutdown", "-h", "now" };
			Pid procId;
			Process.spawn_async(null, argv, null, SpawnFlags.SEARCH_PATH, null, out procId);
			return true;
		}
		catch (Error e) {
			log_error (e.message);
			return false;
		}
	}

	// timers --------------------------------------------------
	
	public GLib.Timer timer_start(){
		var timer = new GLib.Timer();
		timer.start();
		return timer;
	}

	public ulong timer_elapsed(GLib.Timer timer, bool stop = true){
		ulong microseconds;
		double seconds;
		seconds = timer.elapsed (out microseconds);
		if (stop){
			timer.stop();
		}
		return (ulong)((seconds * 1000 ) + (microseconds / 1000));
	}

	public void sleep(int milliseconds){
		Thread.usleep ((ulong) milliseconds * 1000);
	}

	public string timer_elapsed_string(GLib.Timer timer, bool stop = true){
		ulong microseconds;
		double seconds;
		seconds = timer.elapsed (out microseconds);
		if (stop){
			timer.stop();
		}
		return "%.0f ms".printf((seconds * 1000 ) + microseconds/1000);
	}
}
