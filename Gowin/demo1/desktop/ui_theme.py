"""Desktop design tokens and shared ttkbootstrap styling."""
import tkinter as tk
import ttkbootstrap as bootstrap
from ttkbootstrap.utils import scale_size

BG = '#0e1520'
PANEL = '#172230'
TILE = '#223247'
INK = '#eaf2fa'
MUTED = '#9aadc4'
ACCENT = '#67dfc2'
BORDER = '#2c3d52'
WARNING = '#f3c17d'
FONT = 'Microsoft YaHei UI'


def configure_theme(app):
    # Register against the live root. App.destroy() resets ttkbootstrap's
    # singleton, so repeated application lifecycles also work in GUI tests.
    bootstrap.Theme(
        name='tang', primary='#39b89c', success='#39b89c', info='#619ee9',
        warning='#dfa651', danger='#dd697b', neutral='#8b9eb6',
        dark={'background': PANEL, 'foreground': INK},
    ).register()
    style = app.style
    style.theme_use('tang-dark')
    style.configure('.', font=(FONT, 10))
    style.configure('TButton', padding=(12, 8), font=(FONT, 10))
    style.configure('TEntry', padding=6, font=(FONT, 10))
    style.configure('TCombobox', padding=6, font=(FONT, 10))
    style.configure('Treeview', rowheight=34, font=(FONT, 10))
    style.configure('Treeview.Heading', padding=(8, 10), font=(FONT, 10, 'bold'))
    app.option_add('*Font', (FONT, 10))
    app.option_add('*TCombobox*Listbox.font', (FONT, 10))
    app.configure(background=BG)


def label(parent, text='', size=10, color=INK, **kwargs):
    return tk.Label(parent, text=text, font=(FONT, size), bg=parent.cget('bg'),
                    fg=color, anchor='w', **kwargs)


def card(parent, padding=18):
    padding = scale_size(parent, padding)
    return tk.Frame(parent, bg=PANEL, padx=padding, pady=padding,
                    highlightthickness=1, highlightbackground=BORDER)


def size_window(window, width, height, minimum):
    """Match pixel geometry to Tk's point-sized fonts on high-DPI displays."""
    screen_w, screen_h = window.winfo_screenwidth(), window.winfo_screenheight()
    width = min(scale_size(window, width), screen_w - scale_size(window, 40))
    height = min(scale_size(window, height), screen_h - scale_size(window, 80))
    window.minsize(min(scale_size(window, minimum[0]), width),
                   min(scale_size(window, minimum[1]), height))
    window.geometry(f'{width}x{height}+{max(0, (screen_w-width)//2)}+{max(0, (screen_h-height)//2-24)}')


def style_text(widget):
    widget.configure(bg=BG, fg=INK, insertbackground=INK, selectbackground=TILE,
                     relief='flat', borderwidth=0, padx=12, pady=10,
                     font=(FONT, 10))


class EnvelopePreview(tk.Canvas):
    """Stage diagram, deliberately not presented as a measured audio waveform."""
    def __init__(self, parent, height=80):
        super().__init__(parent, height=scale_size(parent, height), bg=BG, highlightthickness=0)
        self.profile = {}
        self.bind('<Configure>', lambda _: self.draw())

    def show(self, profile):
        values = {k: profile.get(k, 0) for k in ('attack', 'decay', 'sustain', 'release')}
        if values != self.profile:
            self.profile = values
            self.draw()

    def draw(self):
        self.delete('all')
        width, height = max(self.winfo_width(), 120), max(self.winfo_height(), 60)
        left, right, top, bottom = 12, width - 12, 12, height - 24
        span = right - left
        sustain = min(100, max(0, self.profile.get('sustain', 0))) / 100
        level = bottom - sustain * (bottom - top)
        xs = [left, left + span * .22, left + span * .46, left + span * .73, right]
        points = [xs[0], bottom, xs[1], top, xs[2], level, xs[3], level, xs[4], bottom]
        for x in xs:
            self.create_line(x, top, x, bottom, fill=BORDER)
        self.create_line(left, bottom, right, bottom, fill=BORDER)
        self.create_polygon(*points, fill='#1b3b3b', outline='')
        self.create_line(*points, fill=ACCENT, width=2)
        for i, name in enumerate(('A', 'D', 'S', 'R')):
            self.create_text((xs[i] + xs[i + 1]) / 2, height - 10,
                             text=name, fill=MUTED, font=(FONT, 9))
