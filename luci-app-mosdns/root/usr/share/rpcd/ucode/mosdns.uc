#!/usr/bin/env ucode

'use strict';

import { popen, mkdir, unlink, writefile, open, stat, readfile } from 'fs';
import { cursor } from 'uci';
import { connect } from 'ubus';

function to_array(val) {
	let res =[];
	if (type(val) == 'array') {
		for (let i = 0; i < length(val); i++) {
			if (type(val[i]) == 'string') {
				let s = replace(val[i], /^\s+|\s+$/g, '');
				if (s != "") push(res, s);
			}
		}
	} else if (type(val) == 'string') {
		let parts = split(val, /[ \t\n]+/);
		for (let i = 0; i < length(parts); i++) {
			if (parts[i] != "") push(res, parts[i]);
		}
	}
	return res;
}

function exec_sys(cmd) {
	let p = popen(cmd + " 2>&1", "r");
	if (!p) return { code: -1, stdout: "" };
	let stdout = p.read("all");
	let code = p.close();
	if (type(stdout) == 'string') {
		stdout = replace(stdout, /^\s+|\s+$/g, '');
	}
	return { code: code, stdout: stdout || "" };
}

function restart_mosdns() {
	let p = popen('(sleep 3; /etc/init.d/mosdns restart) >/dev/null 2>&1 &', 'r');
	if (p) p.close();
}

function dump_v2dat_internal() {
	mkdir('/var/mosdns', 0755);
	exec_sys('rm -f /var/mosdns/geo*.txt');

	let uci_cursor = cursor();
	uci_cursor.load('mosdns');
	let v2dat_dir = uci_cursor.get('mosdns', 'config', 'geodat_path') || '/usr/share/v2ray';
	let configfile = uci_cursor.get('mosdns', 'config', 'configfile') || '/var/etc/mosdns.json';
	let adblock = uci_cursor.get('mosdns', 'config', 'adblock');
	let ad_source = uci_cursor.get('mosdns', 'config', 'ad_source') || "";
	let streaming_media = uci_cursor.get('mosdns', 'config', 'custom_stream_media_dns');

	let errors =[];

	if (configfile === "/var/etc/mosdns.json") {
		let res1 = exec_sys(`v2dat unpack geoip -o /var/mosdns -f cn ${v2dat_dir}/geoip.dat`);
		if (res1.code !== 0) push(errors, "geoip cn: " + res1.stdout);

		let res2 = exec_sys(`v2dat unpack geosite -o /var/mosdns -f cn -f apple -f 'geolocation-!cn' ${v2dat_dir}/geosite.dat`);
		if (res2.code !== 0) push(errors, "geosite cn/apple/!cn: " + res2.stdout);

		if (adblock === '1' && index(ad_source, 'geosite.dat') !== -1) {
			let res3 = exec_sys(`v2dat unpack geosite -o /var/mosdns -f category-ads-all ${v2dat_dir}/geosite.dat`);
			if (res3.code !== 0) push(errors, "geosite ads: " + res3.stdout);
		}

		if (streaming_media === '1') {
			let res4 = exec_sys(`v2dat unpack geosite -o /var/mosdns -f netflix -f disney -f hulu ${v2dat_dir}/geosite.dat`);
			if (res4.code !== 0) push(errors, "geosite streaming: " + res4.stdout);
		} else {
			writefile('/var/mosdns/geosite_disney.txt', '');
			writefile('/var/mosdns/geosite_netflix.txt', '');
			writefile('/var/mosdns/geosite_hulu.txt', '');
		}
	} else {
		let res1 = exec_sys(`v2dat unpack geoip -o /var/mosdns -f cn ${v2dat_dir}/geoip.dat`);
		if (res1.code !== 0) push(errors, "geoip cn: " + res1.stdout);

		let res2 = exec_sys(`v2dat unpack geosite -o /var/mosdns -f cn -f 'geolocation-!cn' ${v2dat_dir}/geosite.dat`);
		if (res2.code !== 0) push(errors, "geosite cn/!cn: " + res2.stdout);

		let geoip_tags = to_array(uci_cursor.get('mosdns', 'config', 'geoip_tags'));
		if (length(geoip_tags) > 0) {
			let tags_str = "-f '" + join("' -f '", geoip_tags) + "'";
			let res3 = exec_sys(`v2dat unpack geoip -o /var/mosdns ${tags_str} ${v2dat_dir}/geoip.dat`);
			if (res3.code !== 0) push(errors, "custom geoip: " + res3.stdout);
		}

		let geosite_tags = to_array(uci_cursor.get('mosdns', 'config', 'geosite_tags'));
		if (length(geosite_tags) > 0) {
			let tags_str = "-f '" + join("' -f '", geosite_tags) + "'";
			let res4 = exec_sys(`v2dat unpack geosite -o /var/mosdns ${tags_str} ${v2dat_dir}/geosite.dat`);
			if (res4.code !== 0) push(errors, "custom geosite: " + res4.stdout);
		}
	}
	return errors;
}

function update_ad_lists_internal() {
	let uci_cursor = cursor();
	uci_cursor.load('mosdns');

	if (uci_cursor.get('mosdns', 'config', 'adblock') !== '1') {
		return false;
	}

	let lock_file = '/var/lock/mosdns_ad_update.lock';
	let ad_source = to_array(uci_cursor.get('mosdns', 'config', 'ad_source'));
	let github_proxy = uci_cursor.get('mosdns', 'config', 'github_proxy') || '';

	mkdir('/etc/mosdns', 0755);
	mkdir('/etc/mosdns/rule', 0755);
	writefile('/etc/mosdns/rule/.ad_source', '');

	if (stat(lock_file)) {
		return false;
	} else {
		writefile(lock_file, '');
	}

	let tmp_res = exec_sys('mktemp -d');
	if (tmp_res.code !== 0) {
		unlink(lock_file);
		die("Failed to create temp directory for adlist.");
	}
	let ad_tmpdir = tmp_res.stdout;
	let has_update = false;
	let download_failed = false;

	for (let i = 0; i < length(ad_source); i++) {
		let url = ad_source[i];
		if (!url) continue;

		if (url !== 'geosite.dat' && index(url, 'file://') !== 0) {
			has_update = true;
			exec_sys(`echo "${url}" >> /etc/mosdns/rule/.ad_source`);

			let parts = split(url, '/');
			let filename = parts[length(parts) - 1];
			let mirror = "";

			if (match(url, /^https:\/\/raw\.githubusercontent\.com/)) {
				mirror = github_proxy ? github_proxy + '/' : '';
			}

			let curl_res = exec_sys(`curl --connect-timeout 5 -m 90 --ipv4 -kfSLo "${ad_tmpdir}/${filename}" "${mirror}${url}"`);
			if (curl_res.code !== 0) {
				download_failed = true;
			}
		}
	}

	if (download_failed) {
		exec_sys(`rm -rf "${ad_tmpdir}"`);
		unlink(lock_file);
		die("Rules download failed.");
	} else {
		if (has_update) {
			mkdir('/etc/mosdns/rule/adlist', 0755);
			exec_sys('rm -rf /etc/mosdns/rule/adlist/*');
			exec_sys(`cp "${ad_tmpdir}"/* /etc/mosdns/rule/adlist/`);
		}
	}

	exec_sys(`rm -rf "${ad_tmpdir}"`);
	unlink(lock_file);

	return has_update;
}

function get_logfile_path_internal() {
	let uci_cursor = cursor();
	uci_cursor.load('mosdns');
	let configfile = uci_cursor.get('mosdns', 'config', 'configfile');

	if (configfile === '/var/etc/mosdns.json' || !configfile) {
		return uci_cursor.get('mosdns', 'config', 'log_file');
	} else {
		return '/var/log/mosdns.log';
	}
	return null;
}

const methods = {
	get_interface_dns: {
		call: function() {
			try {
				let uci_cursor = cursor();
				uci_cursor.load('mosdns');
				if (uci_cursor.get('mosdns', 'config', 'custom_local_dns') === '1') {
					let local_dns = to_array(uci_cursor.get('mosdns', 'config', 'local_dns'));
					return { dns: local_dns };
				}

				uci_cursor.load('network');
				let peerdns = uci_cursor.get('network', 'wan', 'peerdns');
				let proto = uci_cursor.get('network', 'wan', 'proto');

				if (peerdns === '0' || proto === 'static') {
					let wan_dns = to_array(uci_cursor.get('network', 'wan', 'dns'));
					return { dns: wan_dns };
				} else {
					let ubus_conn = connect();
					if (ubus_conn) {
						let status = ubus_conn.call('network.interface.wan', 'status');
						if (status && type(status['dns-server']) == 'array' && length(status['dns-server']) > 0) {
							return { dns: status['dns-server'] };
						}
					}
				}
			} catch (e) {
				return { dns:['119.29.29.29', '223.5.5.5'], error: String(e) };
			}
			return { dns:['119.29.29.29', '223.5.5.5'] };
		}
	},

	get_adlist: {
		call: function() {
			try {
				let uci_cursor = cursor();
				uci_cursor.load('mosdns');
				let adblock = uci_cursor.get('mosdns', 'config', 'adblock');

				if (adblock !== '1') {
					mkdir('/etc/mosdns', 0755);
					mkdir('/etc/mosdns/rule', 0755);
					unlink('/etc/mosdns/rule/adlist');
					unlink('/etc/mosdns/rule/.ad_source');
					writefile('/var/mosdns/disable-ads.txt', '');
					return { adlist:['/var/mosdns/disable-ads.txt'] };
				}

				mkdir('/etc/mosdns', 0755);
				mkdir('/etc/mosdns/rule', 0755);
				mkdir('/etc/mosdns/rule/adlist', 0755);

				let ad_source = to_array(uci_cursor.get('mosdns', 'config', 'ad_source'));
				let adlist =[];

				for (let i = 0; i < length(ad_source); i++) {
					let url = ad_source[i];
					if (!url) continue;

					if (url === 'geosite.dat') {
						push(adlist, '/var/mosdns/geosite_category-ads-all.txt');
					} else if (index(url, 'file://') === 0) {
						push(adlist, substr(url, 7));
					} else {
						let parts = split(url, '/');
						let filename = parts[length(parts) - 1];
						let local_path = `/etc/mosdns/rule/adlist/${filename}`;

						if (!stat(local_path)) {
							writefile(local_path, '');
						}
						push(adlist, local_path);
					}
				}
				return { adlist: adlist };
			} catch (e) {
				return { error: String(e) };
			}
		}
	},

	update_remote_resources: {
		args: { background: 0 },
		call: function(req) {
			if (req && req.args.background == 1) {
				let p = popen('ubus -t 120 call luci.mosdns update_remote_resources >/var/log/mosdns_update.log 2>&1 &', 'r');
				if (p) p.close();
				return { success: true, message: 'GeoData update task is running in background.' };
			}

			try {
				let uci_cursor = cursor();
				uci_cursor.load('mosdns');

				let github_proxy = uci_cursor.get('mosdns', 'config', 'github_proxy') || '';
				let mirror = github_proxy ? github_proxy + '/' : '';
				let geoip_type = uci_cursor.get('mosdns', 'config', 'geoip_type') || 'geoip-only-cn-private';
				let v2dat_dir = uci_cursor.get('mosdns', 'config', 'geodat_path') || '/usr/share/v2ray';

				let tmp_res = exec_sys('mktemp -d');
				if (tmp_res.code !== 0) return { status: 'error', message: 'Failed to create temp directory.' };
				let tmpdir = tmp_res.stdout;

				let geoip_url = mirror + "https://github.com/Loyalsoldier/geoip/releases/latest/download/" + geoip_type + ".dat";
				let geosite_url = mirror + "https://github.com/Loyalsoldier/v2ray-rules-dat/releases/latest/download/geosite.dat";

				let res = exec_sys(`curl --connect-timeout 5 -m 120 --ipv4 -kfSLo "${tmpdir}/geoip.dat" "${geoip_url}"`);
				if (res.code !== 0) {
					exec_sys(`rm -rf "${tmpdir}"`);
					return { success: false, message: 'GeoIP download failed.' };
				}

				res = exec_sys(`curl --connect-timeout 5 -m 20 --ipv4 -kfSLo "${tmpdir}/geoip.dat.sha256sum" "${geoip_url}.sha256sum"`);
				if (res.code !== 0) {
					exec_sys(`rm -rf "${tmpdir}"`);
					return { success: false, message: 'GeoIP checksum download failed.' };
				}

				let sum_local = split(exec_sys(`sha256sum "${tmpdir}/geoip.dat"`).stdout, /[ \t\n]+/)[0];
				let sum_remote = split(exec_sys(`cat "${tmpdir}/geoip.dat.sha256sum"`).stdout, /[ \t\n]+/)[0];
				if (sum_local !== sum_remote) {
					exec_sys(`rm -rf "${tmpdir}"`);
					return { success: false, message: 'geoip.dat checksum error' };
				}

				res = exec_sys(`curl --connect-timeout 5 -m 120 --ipv4 -kfSLo "${tmpdir}/geosite.dat" "${geosite_url}"`);
				if (res.code !== 0) {
					exec_sys(`rm -rf "${tmpdir}"`);
					return { success: false, message: 'Geosite download failed.' };
				}

				res = exec_sys(`curl --connect-timeout 5 -m 20 --ipv4 -kfSLo "${tmpdir}/geosite.dat.sha256sum" "${geosite_url}.sha256sum"`);
				if (res.code !== 0) {
					exec_sys(`rm -rf "${tmpdir}"`);
					return { success: false, message: 'Geosite checksum download failed.' };
				}

				sum_local = split(exec_sys(`sha256sum "${tmpdir}/geosite.dat"`).stdout, /[ \t\n]+/)[0];
				sum_remote = split(exec_sys(`cat "${tmpdir}/geosite.dat.sha256sum"`).stdout, /[ \t\n]+/)[0];
				if (sum_local !== sum_remote) {
					exec_sys(`rm -rf "${tmpdir}"`);
					return { success: false, message: 'geosite.dat checksum error' };
				}

				exec_sys(`rm -rf "${tmpdir}"/*.sha256sum`);
				mkdir(v2dat_dir, 0755);
				exec_sys(`cp -a "${tmpdir}"/* "${v2dat_dir}/"`);
				exec_sys(`rm -rf "${tmpdir}"`);

				try {
					update_ad_lists_internal();
				} catch(e) {
					return { success: false, message: 'Geo files updated, but adlist failed: ' + String(e) };
				}

				restart_mosdns();

				return { success: true };
			} catch (e) {
				return { success: false, message: String(e) };
			}
		}
	},

	update_adlist: {
		args: { background: 0 },
		call: function(req) {
			if (req && req.args.background == 1) {
				let p = popen('ubus -t 120 call luci.mosdns update_adlist >/var/log/mosdns_adlist_update.log 2>&1 &', 'r');
				if (p) p.close();
				return { success: true, message: 'Adlist update task is running in background.' };
			}

			try {
				let has_update = update_ad_lists_internal();
				if (has_update) {
					restart_mosdns();
					return { success: true };
				} else {
					return { status: 'no_update', message: 'Adlist has no update or is currently locked.' };
				}
			} catch (e) {
				return { success: false, message: String(e) };
			}
		}
	},

	flush_cache: {
		call: function() {
			try {
				let uci_cursor = cursor();
				uci_cursor.load('mosdns');
				let port = uci_cursor.get('mosdns', 'config', 'listen_port_api');
				if (!port) return { error: "API listen port not configured." };

				let res = exec_sys(`curl -s 127.0.0.1:${port}/plugins/lazy_cache/flush`);
				if (res.code === 0) {
					return { success: true };
				} else {
					return { success: false, error: res.stdout };
				}
			} catch (e) {
				return { error: String(e) };
			}
		}
	},

	dump_v2dat: {
		call: function() {
			try {
				let errs = dump_v2dat_internal();
				if (length(errs) > 0) {
					return { success: true, warnings: errs };
				}
				return { success: true };
			} catch (e) {
				return { success: false, error: String(e) };
			}
		}
	},

	print_log: {
		call: function() {
			try {
				let path = get_logfile_path_internal();
				if (path && stat(path)) {
					return { log: readfile(path) };
				} else {
					return { error: 'Log file not accessible or does not exist.' };
				}
			} catch (e) {
				return { error: String(e) };
			}
		}
	},

	clean_log: {
		call: function() {
			try {
				let path = get_logfile_path_internal();
				if (path) {
					writefile(path, '');
					return { success: true };
				} else {
					return { error: 'Log file path could not be determined.' };
				}
			} catch (e) {
				return { error: String(e) };
			}
		}
	},

	get_version: {
		call: function() {
			let res = exec_sys('mosdns version');
			if (res.code === 0) {
				return { version: res.stdout };
			} else {
				return { error: res.stdout };
			}
		}
	},

	restart: {
		call: function() {
			restart_mosdns();
			return { code: 0, output: "mosdns is restarting in background." };
		}
	}
};

return { "luci.mosdns": methods };
