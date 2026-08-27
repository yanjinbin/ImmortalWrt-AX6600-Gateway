'use strict';
'require view';
'require dom';
'require ui';
'require form';
'require rpc';

var formData = {
	password: {
		pw1: null,
		pw2: null
	},
	loginDays: 365
};

var callSetPassword = rpc.declare({
	object: 'luci',
	method: 'setPassword',
	params: [ 'username', 'password' ],
	expect: { result: false }
});

var callUciGet = rpc.declare({
	object: 'uci',
	method: 'get',
	params: [ 'config', 'section', 'option' ]
});

var callUciSet = rpc.declare({
	object: 'uci',
	method: 'set',
	params: [ 'config', 'section', 'option', 'value' ]
});

var callUciCommit = rpc.declare({
	object: 'uci',
	method: 'commit',
	params: [ 'config' ]
});

return view.extend({
	checkPassword: function(section_id, value) {
		var strength = document.querySelector('.cbi-value-description'),
		    strongRegex = new RegExp("^(?=.{8,})(?=.*[A-Z])(?=.*[a-z])(?=.*[0-9])(?=.*\\W).*$", "g"),
		    mediumRegex = new RegExp("^(?=.{7,})(((?=.*[A-Z])(?=.*[a-z]))|((?=.*[A-Z])(?=.*[0-9]))|((?=.*[a-z])(?=.*[0-9]))).*$", "g"),
		    enoughRegex = new RegExp("(?=.{6,}).*", "g");

		if (strength && value.length) {
			if (false == enoughRegex.test(value))
				strength.innerHTML = '%s: <span style="color:red">%s</span>'.format(_('Password strength'), _('More Characters'));
			else if (strongRegex.test(value))
				strength.innerHTML = '%s: <span style="color:green">%s</span>'.format(_('Password strength'), _('Strong'));
			else if (mediumRegex.test(value))
				strength.innerHTML = '%s: <span style="color:orange">%s</span>'.format(_('Password strength'), _('Medium'));
			else
				strength.innerHTML = '%s: <span style="color:red">%s</span>'.format(_('Password strength'), _('Weak'));
		}

		return true;
	},

	render: function() {
		var m, s, o;
		var uiLangZh = ((document.documentElement.lang || 'en').toLowerCase().indexOf('zh') === 0);
		var loginDaysLabel = uiLangZh ? '登录时长（天）' : 'Login duration (days)';
		var loginDaysDesc = uiLangZh
			? 'LuCI 登录 Cookie 保持有效天数，到期需重新输入密码。默认 365 天。服务器会话本身不变。'
			: 'Days the LuCI login cookie stays valid without re-entering the password. Default: 365. The server session itself is unchanged.';

		m = new form.JSONMap(formData, _('Router Password'), _('Changes the administrator password for accessing the device'));
		m.readonly = !L.hasViewPermission();

		s = m.section(form.NamedSection, 'password', 'password');

		o = s.option(form.Value, 'pw1', _('Password'));
		o.password = true;
		o.validate = this.checkPassword;

		o = s.option(form.Value, 'loginDays', loginDaysLabel);
		o.datatype = 'uinteger';
		o.optional = true;
		o.description = loginDaysDesc;

		o = s.option(form.Value, 'pw2', _('Confirmation'), ' ');
		o.password = true;
		o.renderWidget = function(/* ... */) {
			var node = form.Value.prototype.renderWidget.apply(this, arguments);

			node.querySelector('input').addEventListener('keydown', function(ev) {
				if (ev.keyCode == 13 && !ev.currentTarget.classList.contains('cbi-input-invalid'))
					document.querySelector('.cbi-button-save').click();
			});

			return node;
		};

		/* 读取现有 cookie_days，避免页面始终显示构建时的默认值。 */
		return callUciGet('luci', 'sauth', 'cookie_days').then(function(result) {
			var configured = result && result.value != null ? result.value : result,
				days = parseInt(configured, 10);

			if (!isNaN(days) && days >= 1 && days <= 3650)
				formData.loginDays = days;

			return m.render();
		}).catch(function() {
			return m.render();
		});
	},

	handleSave: function() {
		var map = document.querySelector('.cbi-map');

		return dom.callClassMethod(map, 'save').then(function() {
			var days = parseInt(formData.loginDays, 10),
			    uci_promise = Promise.resolve();

			if (!isNaN(days) && days >= 1 && days <= 3650)
				uci_promise = callUciSet('luci', 'sauth', 'cookie_days', String(days)).then(function() {
					return callUciCommit('luci');
				});

			return uci_promise.then(function() {
				if (formData.password.pw1 == null || formData.password.pw1.length == 0)
					return;

				if (formData.password.pw1 != formData.password.pw2) {
					ui.addNotification(null, E('p', _('Given password confirmation did not match, password not changed!')), 'danger');
					return;
				}

				return callSetPassword('root', formData.password.pw1).then(function(success) {
					if (success)
						ui.addNotification(null, E('p', _('The system password has been successfully changed.')), 'info');
					else
						ui.addNotification(null, E('p', _('Failed to change the system password.')), 'danger');

					formData.password.pw1 = null;
					formData.password.pw2 = null;

					dom.callClassMethod(map, 'render');
				});
			});
		});
	},

	handleSaveApply: null,
	handleReset: null
});
