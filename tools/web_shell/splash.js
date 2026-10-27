/* Ginger Games loading screen driver.
 *
 * Inlined into Godot's web shell by tools/export_web_mobile.py.  The exporter
 * also adds one line inside the shell's own onProgress callback:
 *
 *     window.gingerSplash && gingerSplash.set(current, total);
 *
 * so the screen follows the real byte counts of the 84 MiB pck and the 38 MiB
 * wasm rather than a timer.  Keep this file free of anything that can throw
 * before the hook is used: a thrown error here would leave the branded screen
 * frozen while the game loads perfectly well behind it.
 *
 * Elements are looked up when they are needed, not when this runs.  In the
 * shipped page the markup is above the script and either way works, but
 * tools/web_shell/preview.html injects the markup asynchronously, and a cached
 * null from parse time there is a screen that never moves -- which is exactly
 * the kind of failure this driver must not have.
 */
(function () {
	var cache = {};

	function element(id) {
		if (!cache[id]) {
			cache[id] = document.getElementById(id);
		}
		return cache[id];
	}

	var shown = -1;
	var revealed = false;

	function apply(fraction) {
		if (isNaN(fraction)) {
			return;
		}
		var value = Math.max(0, Math.min(1, fraction));
		var percent = Math.round(value * 100);
		var livery = element('ginger-livery');

		/* The horse arrives as the screen does, not on the first byte: the wait
		   for that first byte is the longest moment on a slow phone, and an empty
		   cream panel is not something to look at. */
		if (!revealed && livery) {
			revealed = true;
			livery.classList.add('is-in');
		}

		if (percent === shown) {
			return;
		}
		shown = percent;

		var bar = element('ginger-bar');
		if (bar) {
			bar.style.setProperty('--ginger-progress', percent + '%');
		}
		var label = element('ginger-percent');
		if (label) {
			label.textContent = percent >= 100 ? 'READY' : 'LOADING ' + percent + '%';
		}
		if (percent >= 100) {
			document.body.classList.add('ginger-loaded');
		}
	}

	window.gingerSplash = {
		set: function (current, total) {
			if (total > 0) {
				apply(current / total);
			}
		},
	};

	/* Draw the empty bar and the puller at its left end before the first byte
	   arrives, so the screen is never a bar with no driver. */
	apply(0);
})();
