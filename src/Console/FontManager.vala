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
	public bool list_only = false;

	public Gee.HashMap<string,Font> fonts;
	
	public FontManager(LinuxDistro _distro, bool _dry_run, bool _list_only){

		distro = _distro;

		dry_run = _dry_run;

		list_only = _list_only;

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


	// save -------------------------------------------

	public bool backup_fonts(string basepath){

		string backup_path = path_combine(basepath, "fonts");

		string system_path = "/usr/share/fonts";

		if (!dry_run){
			dir_create(backup_path);
		}

		if (!dry_run){
			log_msg(_("Copying installed fonts..."));
		}

		// system fonts --------------------------

		backup_fonts_from_path(system_path, backup_path);

		// users' fonts -------------------------
		
		var mgr = new UserManager();
		mgr.query_users(false);
		
		foreach(var user in mgr.users.values){

			if (user.is_system) { continue; }
			
			string path = "%s/.fonts".printf(user.home_path);
			backup_fonts_from_path(path, backup_path);

			path = "%s/.local/share/fonts".printf(user.home_path);
			backup_fonts_from_path(path, backup_path);
		}

		if (dry_run){
			log_msg(_("Nothing to do (--dry-run mode)"));
			log_msg(string.nfill(70,'-'));
		}
		else{
			log_msg(Message.BACKUP_OK);
			log_msg(string.nfill(70,'-'));
		}

		return true;
	}
	
	public bool backup_fonts_from_path(string system_path, string backup_path){

		if (!dir_exists(system_path)){ return false; }

		log_msg("%s: %s".printf(_("Path"), system_path));

		string cmd = "rsync -ai --numeric-ids";
		
		cmd += " -L"; // dereference symlinks to font files

		if (dry_run){
			cmd += " --dry-run";
		}
		
		cmd += " --exclude=cmap/ --exclude=type1/ --exclude=X11/";
		cmd += " '%s/'".printf(escape_single_quote(system_path));
		cmd += " '%s/'".printf(escape_single_quote(backup_path));

		int status = Posix.system(cmd);

		log_msg(string.nfill(70,'-'));

		return (status == 0);
	}

	// restore ---------------------------------------
	
	public bool restore_fonts(string basepath){

		string backup_path = path_combine(basepath, "fonts");

		string system_path = "/usr/share/fonts";
		
		if (!dir_exists(backup_path)){
			log_error("%s: %s".printf(_("Directory not found"), backup_path));
			return false;
		}

		if (!dry_run){
			log_msg(_("Installing fonts..."));
		}
	
		string cmd = "rsync -ai --numeric-ids";

		cmd += " --ignore-existing";

		if (dry_run){
			cmd += " --dry-run";
		}
		
		cmd += " --exclude=cmap/ --exclude=type1/ --exclude=X11/";
		cmd += " '%s/'".printf(escape_single_quote(backup_path));
		cmd += " '%s/'".printf(escape_single_quote(system_path));

		log_debug(cmd);
		int status = Posix.system(cmd);
		log_msg(string.nfill(70,'-'));

		if (!dry_run){
			cmd = "fc-cache -fv";
			log_debug(cmd);
			status = Posix.system(cmd);
			log_msg(string.nfill(70,'-'));
		}

		if (dry_run){
			log_msg(_("Nothing to do (--dry-run mode)"));
			log_msg(string.nfill(70,'-'));
		}
		else{
			log_msg(Message.RESTORE_OK);
			log_msg(string.nfill(70,'-'));
		}
		
		return (status == 0);
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
