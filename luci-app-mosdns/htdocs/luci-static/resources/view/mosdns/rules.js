'use strict';
'require form';
'require fs';
'require ui';
'require view';
'require rpc';

const callRestart = rpc.declare({
	object: 'luci.mosdns',
	method: 'restart'
});

return view.extend({
	render() {
		const m = new form.Map('mosdns', _('Rule Settings'),
			_('Except for the lists defined by Sbwml, the other \'GfwPlusLists, RemoteQueryLists, Known Lists, and ExcludeGfwlists\' are only applicable to \'Custom Config\' profiles.'));

		const s = m.section(form.TypedSection);
		s.anonymous = true;
		s.sortable = true;

		const handleSaveError = e => {
			ui.addNotification(null, E('p', _('Unable to save contents: %s').format(e.message)));
		};

		// 整合所有 12 个规则文件及对应描述
		const rules = [
			{
				name: 'whitelist',
				title: _('White Lists'),
				file: '/etc/mosdns/rule/whitelist.txt',
				desc: _('Added domain names always permit resolution using \'local DNS\' with the highest priority (one domain per line, supports domain matching rules).')
			},
			{
				name: 'blocklist',
				title: _('Block Lists'),
				file: '/etc/mosdns/rule/blocklist.txt',
				desc: _('Added domain names will block DNS resolution (one domain per line, supports domain matching rules).')
			},
			{
				name: 'greylist',
				title: _('Grey Lists'),
				file: '/etc/mosdns/rule/greylist.txt',
				desc: _('Added domain names will always use \'Remote DNS\' for resolution (one domain per line, supports domain matching rules), and can add nftable sets greylist yet.')
			},
			{
				name: 'gfwpluslist',
				title: _('GfwPlusLists'),
				file: '/etc/mosdns/rule/gfwplus_list.txt',
				desc: _('Added domain names will always use \'Remote DNS\' for resolution (one domain per line, supports domain matching rules), and add nftable sets gfwlist.')
			},
			{
				name: 'remotequerylist',
				title: _('RemoteQueryLists'),
				file: '/etc/mosdns/rule/remotelist.txt',
				desc: _('Added domain names will always use \'Remote DNS\' for resolution, and return IPv4 only (one domain per line, supports domain matching rules).')
			},
			{
				name: 'streamingmedialist',
				title: _('Streaming Media'),
				file: '/etc/mosdns/rule/streaming.txt',
				desc: _('When enabling \'Custom Stream Media DNS\', added domains will always use the \'Streaming Media DNS server\' for resolution (one domain per line, supports domain matching rules).')
			},
			{
				name: 'knownlist',
				title: _('Known Lists'),
				file: '/etc/mosdns/rule/knownlist.txt',
				desc: _('Known domain lists, forward to local DNS query(one domain per line, supports domain matching rules).')
			},
			{
				name: 'ddnslist',
				title: _('DDNS Lists'),
				file: '/etc/mosdns/rule/ddnslist.txt',
				desc: _('Added domain names will always use \'Local DNS\' for resolution, with a forced TTL of 5 seconds (one domain per line, supports domain matching rules).')
			},
			{
				name: 'hostslist',
				title: _('Hosts'),
				file: '/etc/mosdns/rule/hosts.txt',
				desc: _('Custom Hosts rewrite, for example: baidu.com 10.0.0.1 (one rule per line, supports domain matching rules).')
			},
			{
				name: 'redirectlist',
				title: _('Redirect'),
				file: '/etc/mosdns/rule/redirect.txt',
				desc: _('Redirecting requests for domain names. Request domain A, but return records for domain B, for example: baidu.com qq.com (one rule per line).')
			},
			{
				name: 'localptrlist',
				title: _('Block PTR'),
				file: '/etc/mosdns/rule/local-ptr.txt',
				desc: _('Added domain names will block PTR requests (one domain per line, supports domain matching rules).')
			},
			{
				name: 'excludegfwlist',
				title: _('ExcludeGfwlists'),
				file: '/etc/mosdns/rule/excludegfw.txt',
				desc: _('Exclude Gfwlist from geodate_gfw.txt(one domain per line, supports domain matching rules).')
			}
		];

		rules.forEach(rule => {
			s.tab(rule.name, rule.title);

			const descHtml = rule.desc ? `<font color='red'>${rule.desc}</font>` : null;
			const o = s.taboption(rule.name, form.TextValue, '_' + rule.name, null, descHtml);
			o.rows = 25;
			o.cfgvalue = () => fs.trimmed(rule.file).catch(() => '');
			o.write = function(section_id, formvalue) {
				return this.cfgvalue(section_id).then(value => {
					if (value === formvalue) {
						return;
					}
					const content = (formvalue && formvalue.trim()) ? formvalue.trim().replace(/\r\n/g, '\n') + '\n' : '';
					return fs.write(rule.file, content).catch(handleSaveError);
				});
			};
			o.remove = () => fs.write(rule.file, '').catch(handleSaveError);
		});

		return m.render();
	},

	// 保留重启 MosDNS 进程的 RPC 调用逻辑（针对无 206 自动重载补丁环境）
	async handleSaveApply(ev) {
		const m = this.map;

		try {
			await this.handleSave(m);
			const res = await callRestart();

			if (res?.code === 0) {
				window.location.reload();
			} else {
				ui.addNotification(null, E('p', _('Failed to restart mosdns: %s').format(res.output || 'Unknown error')));
			}
		} catch (e) {
			ui.addNotification(null, E('p', _('Error: %s').format(e.message)));
		}
	},

	handleReset: null
});
