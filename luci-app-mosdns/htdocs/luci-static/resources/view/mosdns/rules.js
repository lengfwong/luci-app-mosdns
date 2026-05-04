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

const ruleFiles = {
    'whitelist': 'whitelist.txt',
    'blocklist': 'blocklist.txt',
    'greylist': 'greylist.txt',
    'ddnslist': 'ddnslist.txt',
    'hostslist': 'hosts.txt',
    'redirectlist': 'redirect.txt',
    'localptrlist': 'local-ptr.txt',
    'streamingmedialist': 'streaming.txt',
    'gfwpluslist': 'gfwplus_list.txt',
    'remotequerylist': 'remotelist.txt',
    'excludegfwlist': 'excludegfw.txt',
    'knownlist': 'knownlist.txt'
};

const descriptions = {
    'whitelist': _('Added domain names always permit resolution using \'local DNS\' with the highest priority...'),
    'blocklist': _('Added domain names will block DNS resolution (one domain per line, supports domain matching rules).'),
    'greylist': _('Added domain names will always use \'Remote DNS\' for resolution (one domain per line, supports domain matching rules), and can add nftable sets greylist yet.'),
    'gfwpluslist': _('Added domain names will always use \'Remote DNS\' for resolution (one domain per line, supports domain matching rules), and add nftable sets gfwlist.'),
    'remotequerylist': _('Added domain names will always use \'Remote DNS\' for resolution, and return IPv4 only (one domain per line, supports domain matching rules).'),
    'streamingmedialist': _('When enabling \'Custom Stream Media DNS\', added domains will always use the \'Streaming Media DNS server\' for resolution (one domain per line, supports domain matching rules).'),
    'knownlist': _('Known domain lists, forward to local DNS query(one domain per line, supports domain matching rules).'),
    'ddnslist': _('Added domain names will always use \'Local DNS\' for resolution, with a forced TTL of 5 seconds (one domain per line, supports domain matching rules).'),
    'hostslist': _('Custom Hosts rewrite, for example: baidu.com 10.0.0.1 (one rule per line, supports domain matching rules).'),
    'redirectlist': _('Redirecting requests for domain names. Request domain A, but return records for domain B, for example: baidu.com qq.com (one rule per line).'),
    'localptrlist': _('Added domain names will block PTR requests (one domain per line, supports domain matching rules).'),
    'excludegfwlist': _('Exclude Gfwlist from geodate_gfw.txt(one domain per line, supports domain matching rules).')
};

return view.extend({
    render() {
        const m = new form.Map("mosdns", _("Rule Settings"),
            _('Except for the lists defined by Sbwml, the other\'GfwPlusLists, RemoteQueryLists, Known Lists, and ExcludeGfwlists\' are only applicable to\'Custom Config\'profiles.'));

        const s = m.section(form.TypedSection);
        s.anonymous = true;
        s.sortable = true;

        s.tab('whitelist', _('White Lists'));
        s.tab('blocklist', _('Block Lists'));
        s.tab('greylist', _('Grey Lists'));
        s.tab('gfwpluslist', _('GfwPlusLists'));
        s.tab('remotequerylist', _('RemoteQueryLists'));
        s.tab('streamingmedialist', _('Streaming Media'));
        s.tab('knownlist', _('Known Lists'));
        s.tab('ddnslist', _('DDNS Lists'));
        s.tab('hostslist', _('Hosts'));
        s.tab('redirectlist', _('Redirect'));
        s.tab('localptrlist', _('Block PTR'));
        s.tab('excludegfwlist', _('ExcludeGfwlists'));

        Object.keys(ruleFiles).forEach(tabName => {
            const fileName = ruleFiles[tabName];
            const filePath = `/etc/mosdns/rule/${fileName}`;
            const desc = descriptions[tabName] || '';

            const o = s.taboption(tabName, form.TextValue, `_${tabName}`, null,
                desc ? `<font color='red'>${desc}</font>` : null);

            o.rows = 25;

            o.cfgvalue = () => fs.trimmed(filePath).catch(() => "");

            o.write = async (section_id, formvalue) => {
                const value = await o.cfgvalue(section_id);
                if (value === formvalue) return;

                const content = formvalue.trim() ? `${formvalue.trim().replace(/\r\n/g, '\n')}\n` : '';
                return fs.write(filePath, content).catch(e => {
                    ui.addNotification(null, E('p', _('Unable to save contents: %s').format(e.message)));
                });
            };

            o.remove = () => fs.write(filePath, '').catch(e => {
                ui.addNotification(null, E('p', _('Unable to save contents: %s').format(e.message)));
            });
        });

        return m.render();
    },

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
