'use strict';
'require form';
'require fs';
'require ui';
'require view';
'require rpc';

var callUpdate = rpc.declare({
	object: 'luci.mosdns',
	method: 'update_remote_resources',
	expect: { '': {} }
});

return view.extend({
	handleUpdate: function () {
		ui.showModal(_('Updating...'), [
			E('p', { 'class': 'spinning' }, _('Please wait, this may take a few moments...')),
		]);
		return callUpdate().then(function (res) {
			ui.hideModal();
			if (res.success) {
				ui.addNotification(null, E('p', res.message || _('Update success')), 'info');
			} else {
				ui.addNotification(null, E('p', res.message || _('Update failed, Please check the network status')), 'error');
			}
		});
	},

	render: function () {
		var m, s, o;

		m = new form.Map('mosdns', _('Update GeoIP & GeoSite databases'),
			_('Automatically update GeoIP and GeoSite databases as well as ad filtering rules through scheduled tasks.'));

		s = m.section(form.TypedSection);
		s.anonymous = true;

		o = s.option(form.Flag, 'geo_auto_update', _('Enable Auto Database Update'));
		o.rmempty = false;

		o = s.option(form.ListValue, 'geo_update_week_time', _('Update Cycle'));
		o.value('*', _('Every Day'));
		o.value('1', _('Every Monday'));
		o.value('2', _('Every Tuesday'));
		o.value('3', _('Every Wednesday'));
		o.value('4', _('Every Thursday'));
		o.value('5', _('Every Friday'));
		o.value('6', _('Every Saturday'));
		o.value('0', _('Every Sunday'));
		o.default = 3;

		o = s.option(form.ListValue, 'geo_update_day_time', _('Update Time'));
		for (let t = 0; t < 24; t++) {
			o.value(t, t + ':00');
		};
		o.default = 3;

		o = s.option(form.ListValue, 'geoip_type', _('GeoIP Type'),
			_('Little: only include Mainland China and Private IP addresses.') +
			'<br>' +
			_('Full: includes all Countries and Private IP addresses.')
			);
		o.value('geoip', _('Full'));
		o.value('geoip-only-cn-private', _('Little'));
		o.rmempty = false;
		o.default = 'geoip';

		o = s.option(form.Value, 'github_proxy', _('GitHub Proxy'),
			_('Update data files with GitHub Proxy, leave blank to disable proxy downloads.'));
		o.value('https://gh-proxy.com', _('https://gh-proxy.com'));
		o.rmempty = true;
		o.default = '';

		o = s.option(form.Button, '_udpate', null,
			_('Check And Update GeoData.'));
		o.title = _('Database Update');
		o.inputtitle = _('Check And Update');
		o.inputstyle = 'apply';
		o.onclick = L.bind(this.handleUpdate, this);

		return m.render();
	}
});
