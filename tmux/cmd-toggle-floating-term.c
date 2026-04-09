/* $OpenBSD$ */

/*
 * Copyright (c) 2024 tmux authors
 *
 * Permission to use, copy, modify, and distribute this software for any
 * purpose with or without fee is hereby granted, provided that the above
 * copyright notice and this permission notice appear in all copies.
 *
 * THE SOFTWARE IS PROVIDED "AS IS" AND THE AUTHOR DISCLAIMS ALL WARRANTIES
 * WITH REGARD TO THIS SOFTWARE INCLUDING ALL IMPLIED WARRANTIES OF
 * MERCHANTABILITY AND FITNESS. IN NO EVENT SHALL THE AUTHOR BE LIABLE FOR
 * ANY SPECIAL, DIRECT, INDIRECT, OR CONSEQUENTIAL DAMAGES OR ANY DAMAGES
 * WHATSOEVER RESULTING FROM LOSS OF MIND, USE, DATA OR PROFITS, WHETHER
 * IN AN ACTION OF CONTRACT, NEGLIGENCE OR OTHER TORTIOUS ACTION, ARISING
 * OUT OF OR IN CONNECTION WITH THE USE OR PERFORMANCE OF THIS SOFTWARE.
 */

#include <sys/types.h>

#include <stdlib.h>
#include <string.h>

#include "tmux.h"

static enum cmd_retval	cmd_toggle_floating_term_exec(struct cmd *,
			    struct cmdq_item *);

const struct cmd_entry cmd_toggle_floating_term_entry = {
	.name = "toggle-floating-term",
	.alias = "tft",

	.args = { "", 0, 0, NULL },
	.usage = "",

	.flags = CMD_CLIENT_CANFAIL,
	.exec = cmd_toggle_floating_term_exec
};

static void
cmd_toggle_floating_term_close_cb(int status, void *arg)
{
	struct client	*c = arg;

	(void)status;
	c->floating_popup = NULL;
	c->floating_popup_visible = 0;
}

static enum cmd_retval
cmd_toggle_floating_term_exec(struct cmd *self, struct cmdq_item *item)
{
	struct client		*c = cmdq_get_client(item);
	struct session		*s;
	const char		*shell;
	u_int			 sx, sy, px, py;
	int			 flags;

	(void)self;

	if (c == NULL || c->session == NULL)
		return (CMD_RETURN_NORMAL);
	s = c->session;

	if (c->floating_popup != NULL) {
		if (c->floating_popup_visible) {
			server_client_hide_overlay(c);
			c->floating_popup_visible = 0;
		} else {
			popup_reattach(c->floating_popup, c);
			c->floating_popup_visible = 1;
		}
		return (CMD_RETURN_NORMAL);
	}

	shell = options_get_string(s->options, "default-shell");
	if (!checkshell(shell))
		shell = _PATH_BSHELL;

	sx = c->tty.sx * 80 / 100;
	sy = c->tty.sy * 75 / 100;
	if (sx < 10)
		sx = 10;
	if (sy < 5)
		sy = 5;
	px = (c->tty.sx - sx) / 2;
	py = (c->tty.sy - sy) / 2;

	flags = POPUP_CLOSEEXIT;

	if (popup_display(flags, BOX_LINES_DEFAULT, NULL, px, py, sx, sy,
	    NULL, shell, 0, NULL, s->cwd, "Floating Terminal", c, s,
	    NULL, NULL, cmd_toggle_floating_term_close_cb, c) != 0)
		return (CMD_RETURN_NORMAL);

	c->floating_popup = c->overlay_data;
	c->floating_popup_visible = 1;
	popup_set_toggle_key(c->floating_popup, 't' | KEYC_META);

	return (CMD_RETURN_NORMAL);
}
