/*
 * FontManager.vala
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

public class FontManager : GLib.Object {
	
	public LinuxDistro distro;
	public bool dry_run = false;
	private string basepath = "";
	
	public Gee.HashMap<string,Font> fonts;

	private bool apply_selections = false;
	private Gee.ArrayList<string> exclude_list = new Gee.ArrayList<string>();
	private Gee.ArrayList<string> include_list = new Gee.ArrayList<string>();
	
	public FontManager(LinuxDistro _distro, bool _dry_run){

		distro = _distro;

		dry_run = _dry_run;

		fonts = new Gee.HashMap<string, Font>();
	}

	public void list_fonts(){

		string cmd = "fc-list : family style";
		string std_out, std_err;
		exec_sync(cmd, out std_out, out std_err);
		
		foreach (string line in std_out.split("\n")){
			
			var match = regex_match("""(.*):style=(.*)""", line);
			
			if (match != null){
				
				string family = match.fetch(1);
				string style = match.fetch(2);

				if (!fonts.has_key(family)){
					fonts[family] = new Font(family);
				}
				
				var font = fonts[family];
				font.add_style(style);
			}
		}

		foreach(var font in fonts_sorted){
			log_msg("%s -- %s".printf(font.family, font.style));
			//log_msg("%s".printf(font.family));
		}
	}

	public Gee.ArrayList<Font> fonts_sorted {
		owned get{
			return get_sorted_array(fonts);
		}
	}

	public string get_backup_path(){
		
		return path_combine(basepath, "fonts");
	}
	
	// save -------------------------------------------

	public bool backup_fonts(string _basepath, PackageManager mgr_pkg, bool _apply_selections){

		basepath = _basepath;

		apply_selections = _apply_selections;

		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Backup"), Messages.TASK_FONTS));
		log_msg(string.nfill(70,'-'));

		// begin ----------------------------
		
		string system_path = "/usr/share/fonts";
		
		string backup_path = init_backup_path();

		string backup_path_files = path_combine(backup_path, "files");
		dir_delete(backup_path_files);
		dir_create(backup_path_files);
		chmod(backup_path_files, "a+rwx");

		read_selections();

		// exclude list for rsync ---------------------------------------

		string list_file = path_combine(backup_path, "exclude.list");
		
		if (App.dist_files.size > 0){

			string txt = "";
			
			foreach(string path in App.dist_files){
				
				if (path.has_prefix("/usr/share/fonts/")){
					
					txt += path["/usr/share/fonts/".length: path.length] + "\n";
				}
			}

			foreach(string path in exclude_list){
				
				if (path.has_prefix("/usr/share/fonts/")){
					
					txt += path["/usr/share/fonts/".length: path.length] + "\n";
				}
			}
			
			file_write(list_file, txt);
			log_msg("%s: %s".printf(_("saved"), list_file.replace(basepath, "$basepath")));
		}

		// print items ------------------------
		
		if (file_exists(list_file)){
			
			foreach(string path in file_read(list_file).split("\n")){
				
				if (path.has_suffix(".ttf") || path.has_suffix(".otf")){
					
					log_msg("%s: %s".printf(_("exclude"), path));
				}
			}

			log_msg("");
		}

		// system fonts --------------------------

		backup_fonts_from_path(system_path, backup_path);

		// users' fonts -------------------------
		
		var mgr = new UserManager();
		mgr.query_users(false);
		
		foreach(var user in mgr.users.values){

			if (user.is_system) { continue; }
			
			string path = "%s/.fonts".printf(user.home_path);
			var list = dir_list_names(path, true);
			if (list.size > 0){
				log_msg(string.nfill(70,'-'));
				backup_fonts_from_path(path, backup_path);
			}
			
			path = "%s/.local/share/fonts".printf(user.home_path);
			list = dir_list_names(path, true);
			if (list.size > 0){
				log_msg(string.nfill(70,'-'));
				backup_fonts_from_path(path, backup_path);
			}
		}

		update_permissions_for_backup_files(backup_path, dry_run);

		log_msg(Messages.BACKUP_OK);

		return true;
	}
	
	public bool backup_fonts_from_path(string system_path, string backup_path){

		if (!dir_exists(system_path)){ return false; }

		log_msg("%s: %s".printf(_("Path"), system_path));
		log_msg("");
		
		string cmd = "rsync -avh";
		
		cmd += " -L"; // dereference symlinks to font files

		if (dry_run){
			cmd += " --dry-run";
		}
		
		cmd += " --exclude=cmap/ --exclude=type1/ --exclude=X11/";

		string exclude_list = path_combine(backup_path, "exclude.list");
		
		if (file_exists(exclude_list)){
			cmd += " --exclude-from='%s'".printf(escape_single_quote(exclude_list));
		}

		cmd += " '%s/'".printf(escape_single_quote(system_path));
		
		cmd += " '%s/files/'".printf(escape_single_quote(backup_path));

		int status = 0;
		
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug(cmd);
			status = Posix.system(cmd);
		}

		log_msg("");

		return (status == 0);
	}

	public bool update_permissions_for_backup_files(string path, bool dry_run) {

		if (dry_run){ return true; }
		
		bool ok = true;
		bool status = true;

		ok = chmod(path, "a+rwx");
		if (!ok){ status = false; }
		
		ok = chmod_dir_contents(path, "d", "a+rwx");
		if (!ok){ status = false; }
		
		ok = chmod_dir_contents(path, "f", "a+rw");
		if (!ok){ status = false; }

		//ok = chown(path, "root", "root");
		//if (!ok){ status = false; }
		
		return status;
	}

	public string init_backup_path(){
		
		string backup_path = get_backup_path();
		
		if (!dir_exists(backup_path)){
			dir_create(backup_path);
			chmod(backup_path, "a+rwx");
		}

		string files_path = path_combine(backup_path, "files");
		dir_delete(files_path);
		dir_create(files_path);
		chmod(files_path, "a+rwx");
		
		return backup_path;
	}

	public void read_selections(){

		include_list.clear();
		exclude_list.clear();
		
		if (!apply_selections){ return; }

		string backup_path = get_backup_path();

		string selections_list = path_combine(backup_path, "selections.list");

		if (!file_exists(selections_list)){ return; }

		foreach(string name in file_read(selections_list).split("\n")){
			if (name.has_prefix("+ ")){
				include_list.add(name[2:name.length]);
			}
			else if (name.has_prefix("- ")){
				exclude_list.add(name[2:name.length]);
			}
		}
	}
	
	// restore ---------------------------------------
	
	public bool restore_fonts(string _basepath, bool _apply_selections){

		basepath = _basepath;

		apply_selections = _apply_selections;
		
		log_msg(string.nfill(70,'-'));
		log_msg("%s: %s".printf(_("Restore"), Messages.TASK_FONTS));
		log_msg(string.nfill(70,'-'));
		
		string backup_path = get_backup_path();

		string system_path = "/usr/share/fonts";
		
		if (!dir_exists(backup_path)){
			log_error("%s: %s".printf(_("Directory not found"), backup_path));
			return false;
		}

		string cmd = "rsync -avh";

		cmd += " --ignore-existing";

		if (dry_run){
			cmd += " --dry-run";
		}
		
		cmd += " --exclude=cmap/ --exclude=type1/ --exclude=X11/";
		cmd += " '%s/files/'".printf(escape_single_quote(backup_path));
		cmd += " '%s/'".printf(escape_single_quote(system_path));

		int status = 0;
	
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug(cmd);
			status = Posix.system(cmd);
		}
		
		log_msg(string.nfill(70,'-'));

		update_permissions_for_restored_files(system_path, dry_run);

		update_font_cache();

		log_msg(Messages.RESTORE_OK);

		return (status == 0);
	}

	private bool update_font_cache(){

		log_msg(_("Updating font cache:"));
		log_msg("");
		
		string cmd = "fc-cache";
		if (!cmd_exists(cmd)){
			log_error("%s: %s".printf(Messages.MISSING_COMMAND, cmd));
			return false;
		}

		cmd = "fc-cache -fv";
		log_debug(cmd);

		int status = 0;
	
		if (dry_run){
			log_msg("$ %s".printf(cmd));
		}
		else{
			log_debug(cmd);
			status = Posix.system(cmd);
		}
	
		log_msg(string.nfill(70,'-'));

		return (status == 0);
	}

	public bool update_permissions_for_restored_files(string path, bool dry_run) {

		if (dry_run){ return true; }
		
		bool ok = true;
		bool status = true;

		ok = chmod(path, "755");
		if (!ok){ status = false; }
		
		ok = chmod_dir_contents(path, "d", "755");
		if (!ok){ status = false; }
		
		ok = chmod_dir_contents(path, "f", "644");
		if (!ok){ status = false; }

		ok = chown(path, "root", "root");
		if (!ok){ status = false; }
		
		return status;
	}
	
	// static ----------------------

	public static Gee.ArrayList<Font> get_sorted_array(Gee.HashMap<string,Font> dict){

		var list = new Gee.ArrayList<Font>();
		
		foreach(var pkg in dict.values) {
			list.add(pkg);
		}

		list.sort((a, b) => {
			return strcmp(a.family.down(), b.family.down());
		});

		return list;
	}

}

public class Font : GLib.Object {
	
	public string family = "";
	public string style = "";

	public Font(string _family){
		family = _family;
	}

	public void add_style(string _style){
		if (style.length > 0){ style += ","; }
		style += _style;
	}
}
