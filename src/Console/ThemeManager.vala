/*
 * ThemeManager.vala
 *
 * Copyright 2012-2017 Tony George <teejeetech@gmail.com>
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

using GLib;
using Gee;

using TeeJee.Logging;
using TeeJee.FileSystem;
using TeeJee.ProcessHelper;
using TeeJee.System;
using TeeJee.Misc;

public class ThemeManager : GLib.Object {

	public Gee.HashMap<string,Theme> themes;
	public string type = "themes";

	public Gee.HashMap<string,string> subtypes;

	public LinuxDistro distro;
	public bool dry_run = false;
	public bool list_only = false;
	
	public ThemeManager(LinuxDistro _distro, bool _dry_run, bool _list_only, string _type){
	
		distro = _distro;

		dry_run = _dry_run;

		list_only = _list_only;

		type = _type;

		themes = new Gee.HashMap<string,Theme>();
		subtypes = new Gee.HashMap<string,string>();
	}
	
	// check -------------------------------------------

	public void check_installed_themes(){

		//if (!list_only){
		//	log_msg("Checking installed themes (%s)...".printf(type));
		//}

		// system themes ------------------------
		
		string path = "%s/%s".printf("/usr/share", type);
		add_themes_from_path(path);

		// user's themes -------------------------
		
		var mgr = new UserManager();
		mgr.query_users(false);
		
		foreach(var user in mgr.users.values){

			if (user.is_system) { continue; }
			
			path = "%s/.%s".printf(user.home_path, type);
			add_themes_from_path(path);

			path = "%s/.local/share/%s".printf(user.home_path, type);
			add_themes_from_path(path);
		}

		foreach(var theme in themes.values){
			if (!subtypes.has_key(theme.name)){
				subtypes[theme.name] = theme.subtypes_desc;
			}
		}
	}

	public void add_themes_from_path(string path){
		
		try {
			var directory = File.new_for_path(path);
			if (!directory.query_exists()){ return; }
			
			var enumerator = directory.enumerate_children("%s".printf(FileAttribute.STANDARD_NAME), 0);
			FileInfo info;

			while ((info = enumerator.next_file()) != null) {
				if (info.get_file_type() == FileType.DIRECTORY) {
					string name = info.get_name();
					switch (name.down()) {
					case "default":
					case "default-hdpi":
					case "default-xdpi":
					case "emacs":
					case "hicolor":
					case "locolor":
					case "highcontrast":
						continue;
					}
					
					var theme = new Theme.from_system(name, path, type);
					theme.is_selected = true;
					themes[name] = theme;
					//Add theme even if type_list size is 0. There may be unknown types (for other desktops like KDE, etc)
				}
			}
		}
		catch (Error e) {
			log_error (e.message);
			log_error ("In: list_themes_from_path()");
		}
	}

	public void check_archived_themes(string basepath) {

		//log_msg("Checking archived themes...");

		string backup_path = "%s/%s".printf(basepath, type);
		add_archived_themes_from_path(backup_path);

		load_index_file(basepath);

		//log_msg("Found: %d".printf(themes.size));
		//log_msg(string.nfill(70,'-'));
	}
	
	public void add_archived_themes_from_path(string path) {
		
		var f = File.new_for_path(path);
		if (!f.query_exists()) {
			string msg = "%s: %s".printf(Message.DIR_MISSING, path);
			log_error(msg);
			return;
		}

		try {
			var directory = File.new_for_path(path);
			var enumerator = directory.enumerate_children("%s".printf(FileAttribute.STANDARD_NAME), 0);
			FileInfo info;

			while ((info = enumerator.next_file()) != null) {
				
				if (info.get_file_type() != FileType.REGULAR) {
					continue;
				}
				if (!info.get_name().has_suffix(".tar.gz")){
					continue;
				}
				
				string file_path = "%s/%s".printf(path, info.get_name());
				string name = info.get_name().replace(".tar.gz", "");

				var theme = new Theme.from_archive(name, file_path, type);
				themes[name] = theme;
			}
		}
		catch (Error e) {
			log_error (e.message);
			log_error ("In: list_themes_archived_from_path()");
		}
	}

	private void load_index_file(string basepath){

		string backup_path = path_combine(basepath, type);
		string index_file = path_combine(backup_path, "index.list");
		
		if (!file_exists(index_file)){ return; }

		string txt = file_read(index_file);
		
		foreach(string line in txt.split("\n")){
			
			string[] arr = line.split(":",2);
			if (arr.length != 2){ continue; }
			
			string theme_name = arr[0].strip();
			string theme_subtypes = arr[1].strip();
			
			if (!subtypes.has_key(theme_name) || (theme_subtypes.length > 0)){
				subtypes[theme_name] = theme_subtypes;
			}
		}

		foreach(var theme in themes.values){
			if (subtypes.has_key(theme.name)){
				theme.load_subtypes(subtypes[theme.name]);
			}
		}
	}

	public Gee.ArrayList<Theme> themes_sorted {
		owned get{

			var list = new Gee.ArrayList<Theme>();
			
			foreach(var item in themes.values) {
				list.add(item);
			}

			list.sort((a, b) => {
				return strcmp(a.name.down(), b.name.down());
			});

			return list;
		}
	}

	// list  --------------------------

	public void list_themes(){

		foreach(var theme in themes_sorted){
			
			log_msg("%-50s -- %s".printf(theme.theme_path, theme.subtypes_desc));
		}
	}

	// save ---------------------------------------

	public bool save_themes(string basepath){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), (type == "themes") ? Message.TASK_THEMES : Message.TASK_ICONS));
		log_msg(string.nfill(70,'-'));

		string backup_path = path_combine(basepath, type);
		dir_delete(backup_path); // remove existing .list files
		dir_create(backup_path);

		foreach(var theme in themes_sorted) {
			if (theme.is_selected) {
				theme.zip(backup_path);
				while (theme.is_running) {
					sleep(500);
				}
			}
		}

		save_index(backup_path);

		log_msg(Message.BACKUP_OK);

		return false;
	}

	public void save_index(string backup_path){

		string index_file = path_combine(backup_path, "index.list");
		
		string txt = "";
		foreach(var theme in themes_sorted){
			if (subtypes.has_key(theme.name)){
				txt += "%s:%s\n".printf(theme.name, subtypes[theme.name]);
			}
		}

		file_write(index_file, txt);
	}

	public bool restore_themes(string basepath){

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), (type == "themes") ? Message.TASK_THEMES : Message.TASK_ICONS));
		log_msg(string.nfill(70,'-'));

		string backup_path = path_combine(basepath, type);
		
		if (!dir_exists(backup_path)) {
			string msg = "%s: %s".printf(Message.DIR_MISSING, backup_path);
			log_error(msg);
			return false;
		}

		foreach(var theme in themes_sorted){

			theme.is_selected = !theme.is_installed;
		}

		foreach(var theme in themes_sorted) {

			if (theme.is_selected && !theme.is_installed) {

				theme.unzip(dry_run);
				
				while (theme.is_running) {
					sleep(500);
				}

				theme.update_permissions(dry_run);
				theme.update_owner(dry_run);
			}
		}

		//Theme.fix_nested_folders(); // Not needed
		log_msg("");
		
		refresh_icon_cache();

		log_msg("");
		
		log_msg(Message.RESTORE_OK);

		return false;
	}

	public bool refresh_icon_cache(){

		string cmd = "gtk-update-icon-cache";
		if (!cmd_exists(cmd)){
			log_error("%s: %s".printf(Message.MISSING_COMMAND, cmd));
			return false;
		}

		cmd = "gtk-update-icon-cache -f /usr/share/icons/*";

		int status = 0;
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}

		return (status == 0);
	}
}

public class Theme : GLib.Object{
	
	public string name = "";
	public string description = "";
	public string type = ""; //'icons' or 'themes'
	
	public const string base_path = "/usr/share";
	public string theme_path = "";
	public string archive_path = "";
	
	public bool is_selected = false;
	public bool is_installed = false;
	
	public Gee.ArrayList<ThemeType> subtypes = new Gee.ArrayList<ThemeType>();
	public string subtypes_desc = "";

	// zip/unzip progress --------
	
	public string err_line;
	public string out_line;
	public string status_line;
	public string status_summary;
	public Gee.ArrayList<string> stdout_lines;
	public Gee.ArrayList<string> stderr_lines;
	public Pid proc_id;
	public DataInputStream dis_out;
	public DataInputStream dis_err;
	public int64 progress_count;
	public int64 progress_total;
	public bool is_running;
	
	public Theme.from_system(string _name, string _path, string _type){
		
		name = _name;
		type = _type;
		theme_path = path_combine(_path, _name);
		
		is_installed = true;
		
		check_installed_subtypes();
		//get_file_count_installed();
	}
	
	public Theme.from_archive(string _name, string _archive_path, string _type){
		
		name = _name;
		type = _type;
		archive_path = _archive_path;

		theme_path = "/usr/share/%s/%s".printf(type, name);

		check_installed();
	}
	
	public Theme(string _name, string _type, string _base_path){
		
		name = _name;
		type = _type;
	}

	private void check_installed_subtypes(){
		
		subtypes = new Gee.ArrayList<ThemeType>();
		subtypes_desc = "";
		
		try {
			var directory = File.new_for_path(theme_path);
			if (!directory.query_exists()){ return; }
			
			var enumerator = directory.enumerate_children("%s".printf(FileAttribute.STANDARD_NAME), 0);
			FileInfo info;

			while ((info = enumerator.next_file()) != null) {
				if ((info.get_file_type() == FileType.DIRECTORY) || (info.get_file_type() == FileType.SYMBOLIC_LINK)){
					
					string dir_name = info.get_name();
					add_subtype(dir_name);
				}
			}

			if (subtypes.size == 0){
				add_subtype(type);
			}
		}
		catch (Error e) {
			log_error (e.message);
			log_error ("In: get_theme_type_from_installed()");
		}
	}

	public void load_subtypes(string subtypes_list){

		subtypes = new Gee.ArrayList<ThemeType>();
		subtypes_desc = "";
		
		foreach(string part in subtypes_list.split(",")){
			add_subtype(part.strip());
		}
	}
	
	private void add_subtype(string dir_name){

		// TODO: Cleanup this method

		if (dir_name.strip().length == 0){ return; }

		switch (dir_name.down()) {
		case "gtk-2.0":
			subtypes.add(ThemeType.GTK20);
			if (subtypes_desc.length > 0){ subtypes_desc += ","; }
			subtypes_desc += dir_name.down();
			break;
		case "gtk-3.0":
			subtypes.add(ThemeType.GTK30);
			if (subtypes_desc.length > 0){ subtypes_desc += ","; }
			subtypes_desc += dir_name.down();
			break;
		case "metacity-1":
			subtypes.add(ThemeType.METACITY1);
			if (subtypes_desc.length > 0){ subtypes_desc += ","; }
			subtypes_desc += dir_name.down();
			break;
		case "unity":
			subtypes.add(ThemeType.UNITY);
			if (subtypes_desc.length > 0){ subtypes_desc += ","; }
			subtypes_desc += dir_name.down();
			break;
		case "cinnamon":
			subtypes.add(ThemeType.CINNAMON);
			if (subtypes_desc.length > 0){ subtypes_desc += ","; }
			subtypes_desc += dir_name.down();
			break;
		case "gnome-shell":
			subtypes.add(ThemeType.GNOMESHELL);
			if (subtypes_desc.length > 0){ subtypes_desc += ","; }
			subtypes_desc += dir_name.down();
			break;
		case "xfce-notify-4.0":
			subtypes.add(ThemeType.XFCENOTIFY40);
			if (subtypes_desc.length > 0){ subtypes_desc += ","; }
			subtypes_desc += dir_name.down();
			break;
		case "xfwm4":
			subtypes.add(ThemeType.XFWM4);
			if (subtypes_desc.length > 0){ subtypes_desc += ","; }
			subtypes_desc += dir_name.down();
			break;
		case "cursors":
			subtypes.add(ThemeType.CURSOR);
			if (subtypes_desc.length > 0){ subtypes_desc += ","; }
			subtypes_desc += dir_name.down();
			break;
		case "actions":
		case "apps":
		case "categories":
		case "devices":
		case "emblems":
		case "mimetypes":
		case "panel":
		case "places":
		case "status":
		case "stock":
		case "16":
		case "16@2x":
		case "16x16":
		case "22":
		case "22@2x":
		case "22x22":
		case "24":
		case "24@2x":
		case "24x24":
		case "32":
		case "32@2x":
		case "32x32":
		case "48":
		case "48@2x":
		case "48x48":
		case "64":
		case "64@2x":
		case "64x64":
		case "128":
		case "128@2x":
		case "128x128":
		case "256":
		case "256@2x":
		case "256x256":
		case "scalable":
		case "icons":
			if (!subtypes.contains(ThemeType.ICON)){
				subtypes.add(ThemeType.ICON);
				if (subtypes_desc.length > 0){ subtypes_desc += ","; }
				subtypes_desc += "icons";
			}
			break;
		}
	}
	
	public bool check_installed(){

		string subfolder = "/usr/share/%s/%s".printf(type, name);

		var f = File.new_for_path(subfolder);
		this.is_installed = f.query_exists();

		return this.is_installed;
	}
	
	// zip and unzip --------------------------

	public bool zip(string backup_path) {
		
		string file_name = name + ".tar.gz";
		string zip_file = path_combine(backup_path, file_name);

		try {
			//create directory
			var f = File.new_for_path(backup_path);
			if (!f.query_exists()) {
				f.make_directory_with_parents();
			}

			// silent -- no -v
			string cmd = "tar czf '%s' -C '%s' '%s' 1> /dev/null".printf(zip_file, file_parent(theme_path), name);
			log_debug(cmd);

			stdout.printf("%-80s".printf(_("Archiving") + " '%s'".printf(theme_path)));
			stdout.flush();

			int status = Posix.system(cmd);
			
			if (status == 0) {
				stdout.printf("[ OK ]\n");
			}
			else {
				stdout.printf("[ status=%d ]\n".printf(status));
			}
			return (status == 0);

		}
		catch (Error e) {
			log_error (e.message);
			return false;
		}
	}
	
	public bool unzip(bool dry_run) {

		//check file
		if (!file_exists(archive_path)) {
			log_error(_("File not found") + ": '%s'".printf(archive_path));
			return false;
		}

		dir_create(theme_path);

		// silent -- no -v
		string cmd = "tar xzf '%s' --directory='%s' 1> /dev/null".printf(archive_path, file_parent(theme_path));

		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
		}
		
		stdout.printf("%-80s".printf(_("Extracting") + " '%s'".printf(theme_path)));
		stdout.flush();

		int status = 0;
		
		if (!dry_run){
			status = Posix.system(cmd);
		}
		
		if (status == 0) {
			stdout.printf("[ OK ]\n");
		}
		else {
			stdout.printf("[ status=%d ]\n".printf(status));
		}
		
		return (status == 0);
	}
	
	//permissions -------------
	
	public bool update_permissions(bool dry_run) {

		string cmd = "";

		//log_debug("set_permission (755)(dirs) : %s".printf(theme_path));
		cmd = "find '%s' -type d -exec chmod 755 '{}' ';'".printf(theme_path);

		int status = 0;
	
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}

		//log_debug("set_permission (644)(files): %s".printf(theme_path));
		cmd = "find '%s' -type f -exec chmod 644 '{}' ';'".printf(theme_path);

		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug("$ %s".printf(cmd));
			status = Posix.system(cmd);
		}

		return (status == 0);
	}
	
	public void update_owner(bool dry_run) {

		if (dry_run){
			log_msg("set_owner (root:root): %s".printf(theme_path));
		}
		else{
			log_debug("set_owner (root:root): %s".printf(theme_path));
			chown(theme_path, "root", "root");
		}
	}

	//enums and helpers ------------------
	
	public static Gee.HashMap<ThemeType, string> theme_type_map;
	
	static construct {
		var map = new Gee.HashMap<ThemeType, string>(); 
		map[ThemeType.ALL] = "all";
		map[ThemeType.NONE] = "none";
		map[ThemeType.CINNAMON] = "cinnamon";
		map[ThemeType.CURSOR] = "cursors";
		map[ThemeType.GNOMESHELL] = "gnome-shell";
		map[ThemeType.GTK20] = "gtk-2.0";
		map[ThemeType.GTK30] = "gtk-3.0";
		map[ThemeType.ICON] = "icons";
		map[ThemeType.METACITY1] = "metacity-1";
		map[ThemeType.UNITY] = "unity";
		map[ThemeType.XFCENOTIFY40] = "xfce-notify-4.0";
		map[ThemeType.XFWM4] = "xfwm4";
		theme_type_map = map;
	}

	public static void fix_nested_folders(){
		fix_nested_folders_in_path("/usr/share/themes");
		fix_nested_folders_in_path("/usr/share/icons");
		fix_nested_folders_in_path("/root/.themes");
		fix_nested_folders_in_path("/root/.icons");
			
		var list = list_dir_names("/home");
		
		foreach(string user_name in list){
			if (user_name == "PinguyBuilder"){
				continue;
			}

			fix_nested_folders_in_path("/home/%s/.themes".printf(user_name));
			fix_nested_folders_in_path("/home/%s/.icons".printf(user_name));
		}
	}
	
	public static void fix_nested_folders_in_path(string share_path){
		try {
			
			log_debug("\n" + _("Checking for nested folders in path") + ": %s".printf(share_path));
			
			var dir = File.new_for_path(share_path);
			if (!dir.query_exists()){
				return;
			}
			
			var enumerator = dir.enumerate_children("%s".printf(FileAttribute.STANDARD_NAME), 0);
			FileInfo info;

			while ((info = enumerator.next_file()) != null) {
				if (info.get_file_type() == FileType.DIRECTORY) {
					string theme_name = info.get_name();

					var theme_dir = "%s/%s".printf(share_path, theme_name);
					var dir2 = File.new_for_path(theme_dir);					
					var enum2 = dir2.enumerate_children("%s".printf(FileAttribute.STANDARD_NAME), 0);
					FileInfo info2;

					bool nested_dir_found = false;
					int subdir_count = 0;
					while ((info2 = enum2.next_file()) != null) {
						subdir_count++;
						if (info2.get_file_type() == FileType.DIRECTORY) {
							if (info2.get_name() == theme_name){
								nested_dir_found = true;
							}
						}
					}

					if (nested_dir_found && (subdir_count == 1)){
						// move the nested folder one level up
						var src = "%s/%s/%s".printf(share_path, theme_name, theme_name);
						var dst = "%s/%s".printf(share_path, theme_name);
						var dst_tmp = "%s/%s_temp".printf(share_path, theme_name);

						if (dir_exists(src)){
							file_move(src, dst_tmp);
						}

						file_delete(dst);
						file_move(dst_tmp, dst);

						log_msg("Fixed: %s".printf(src));
					}
				}
			}
		}
		catch (Error e) {
			log_error (e.message);
			log_error ("Theme: fix_nested_folders_in_path()");
		}
	}



}

public enum ThemeType {
	ALL,
	NONE,
	CINNAMON,
	CURSOR,
	GNOMESHELL,
	GTK20,
	GTK30,
	ICON,
	THEME,
	METACITY1,
	UNITY,
	XFCENOTIFY40,
	XFWM4
}


	
