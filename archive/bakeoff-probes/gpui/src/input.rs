//! Minimal IME-capable text field (EntityInputHandler → text-input-v3 via gpui's wayland client).
//! Trimmed from gpui's examples/input.rs (Apache-2.0).

use std::ops::Range;

use gpui::{
    App, Bounds, Context, CursorStyle, ElementId, ElementInputHandler, Entity, EntityInputHandler,
    FocusHandle, Focusable, GlobalElementId, Hsla, LayoutId, MouseButton, MouseDownEvent,
    PaintQuad, Pixels, Point, ShapedLine, SharedString, Style, TextRun, UTF16Selection,
    UnderlineStyle, Window, actions, div, fill, point, prelude::*, px, relative, size,
};

actions!(probe_input, [Backspace, Delete, Left, Right, Home, End]);

pub fn bindings() -> Vec<gpui::KeyBinding> {
    vec![
        gpui::KeyBinding::new("backspace", Backspace, Some("ProbeInput")),
        gpui::KeyBinding::new("delete", Delete, Some("ProbeInput")),
        gpui::KeyBinding::new("left", Left, Some("ProbeInput")),
        gpui::KeyBinding::new("right", Right, Some("ProbeInput")),
        gpui::KeyBinding::new("home", Home, Some("ProbeInput")),
        gpui::KeyBinding::new("end", End, Some("ProbeInput")),
    ]
}

pub struct TextInput {
    pub focus_handle: FocusHandle,
    content: SharedString,
    placeholder: SharedString,
    cursor: usize,
    marked_range: Option<Range<usize>>,
    last_layout: Option<ShapedLine>,
    last_bounds: Option<Bounds<Pixels>>,
    pub fg: Hsla,
    pub hint: Hsla,
    pub bg: Hsla,
    pub family: SharedString,
}

impl TextInput {
    pub fn new(cx: &mut Context<Self>, placeholder: &str, fg: Hsla, hint: Hsla, bg: Hsla, family: String) -> Self {
        Self {
            focus_handle: cx.focus_handle(),
            content: "".into(),
            placeholder: placeholder.to_string().into(),
            cursor: 0,
            marked_range: None,
            last_layout: None,
            last_bounds: None,
            fg,
            hint,
            bg,
            family: family.into(),
        }
    }

    fn prev(&self, o: usize) -> usize {
        self.content[..o].char_indices().next_back().map(|(i, _)| i).unwrap_or(0)
    }
    fn next(&self, o: usize) -> usize {
        self.content[o..].chars().next().map(|c| o + c.len_utf8()).unwrap_or(o)
    }
    fn left(&mut self, _: &Left, _: &mut Window, cx: &mut Context<Self>) {
        self.cursor = self.prev(self.cursor);
        cx.notify();
    }
    fn right(&mut self, _: &Right, _: &mut Window, cx: &mut Context<Self>) {
        self.cursor = self.next(self.cursor);
        cx.notify();
    }
    fn home(&mut self, _: &Home, _: &mut Window, cx: &mut Context<Self>) {
        self.cursor = 0;
        cx.notify();
    }
    fn end(&mut self, _: &End, _: &mut Window, cx: &mut Context<Self>) {
        self.cursor = self.content.len();
        cx.notify();
    }
    fn backspace(&mut self, _: &Backspace, _: &mut Window, cx: &mut Context<Self>) {
        let p = self.prev(self.cursor);
        self.splice(p..self.cursor, "");
        cx.notify();
    }
    fn delete(&mut self, _: &Delete, _: &mut Window, cx: &mut Context<Self>) {
        let n = self.next(self.cursor);
        self.splice(self.cursor..n, "");
        cx.notify();
    }
    fn splice(&mut self, r: Range<usize>, new: &str) {
        self.content = format!("{}{}{}", &self.content[..r.start], new, &self.content[r.end..]).into();
        self.cursor = r.start + new.len();
        self.marked_range = None;
    }
    fn on_mouse_down(&mut self, e: &MouseDownEvent, _: &mut Window, cx: &mut Context<Self>) {
        if let (Some(b), Some(l)) = (self.last_bounds, self.last_layout.as_ref()) {
            self.cursor = l.closest_index_for_x(e.position.x - b.left());
        }
        cx.notify();
    }

    fn off_from_u16(&self, off: usize) -> usize {
        let (mut u8o, mut u16c) = (0, 0);
        for ch in self.content.chars() {
            if u16c >= off {
                break;
            }
            u16c += ch.len_utf16();
            u8o += ch.len_utf8();
        }
        u8o
    }
    fn off_to_u16(&self, off: usize) -> usize {
        let (mut u16o, mut u8c) = (0, 0);
        for ch in self.content.chars() {
            if u8c >= off {
                break;
            }
            u8c += ch.len_utf8();
            u16o += ch.len_utf16();
        }
        u16o
    }
    fn r_from(&self, r: &Range<usize>) -> Range<usize> {
        self.off_from_u16(r.start)..self.off_from_u16(r.end)
    }
    fn r_to(&self, r: &Range<usize>) -> Range<usize> {
        self.off_to_u16(r.start)..self.off_to_u16(r.end)
    }
}

impl EntityInputHandler for TextInput {
    fn text_for_range(
        &mut self,
        r: Range<usize>,
        actual: &mut Option<Range<usize>>,
        _: &mut Window,
        _: &mut Context<Self>,
    ) -> Option<String> {
        let r = self.r_from(&r);
        actual.replace(self.r_to(&r));
        Some(self.content[r].to_string())
    }
    fn selected_text_range(&mut self, _: bool, _: &mut Window, _: &mut Context<Self>) -> Option<UTF16Selection> {
        let o = self.off_to_u16(self.cursor);
        Some(UTF16Selection { range: o..o, reversed: false })
    }
    fn marked_text_range(&self, _: &mut Window, _: &mut Context<Self>) -> Option<Range<usize>> {
        self.marked_range.as_ref().map(|r| self.r_to(r))
    }
    fn unmark_text(&mut self, _: &mut Window, _: &mut Context<Self>) {
        self.marked_range = None;
    }
    fn replace_text_in_range(&mut self, r: Option<Range<usize>>, new: &str, _: &mut Window, cx: &mut Context<Self>) {
        let r = r
            .as_ref()
            .map(|r| self.r_from(r))
            .or(self.marked_range.clone())
            .unwrap_or(self.cursor..self.cursor);
        self.splice(r, new);
        cx.notify();
    }
    fn replace_and_mark_text_in_range(
        &mut self,
        r: Option<Range<usize>>,
        new: &str,
        sel: Option<Range<usize>>,
        _: &mut Window,
        cx: &mut Context<Self>,
    ) {
        let r = r
            .as_ref()
            .map(|r| self.r_from(r))
            .or(self.marked_range.clone())
            .unwrap_or(self.cursor..self.cursor);
        let start = r.start;
        self.splice(r, new);
        self.marked_range = if new.is_empty() { None } else { Some(start..start + new.len()) };
        if let Some(s) = sel {
            self.cursor = start + self.off_from_u16(s.end).min(new.len());
        }
        cx.notify();
    }
    fn bounds_for_range(&mut self, r: Range<usize>, bounds: Bounds<Pixels>, _: &mut Window, _: &mut Context<Self>) -> Option<Bounds<Pixels>> {
        let l = self.last_layout.as_ref()?;
        let r = self.r_from(&r);
        Some(Bounds::from_corners(
            point(bounds.left() + l.x_for_index(r.start), bounds.top()),
            point(bounds.left() + l.x_for_index(r.end), bounds.bottom()),
        ))
    }
    fn character_index_for_point(&mut self, p: Point<Pixels>, _: &mut Window, _: &mut Context<Self>) -> Option<usize> {
        let lp = self.last_bounds?.localize(&p)?;
        let l = self.last_layout.as_ref()?;
        let i = l.index_for_x(p.x - lp.x)?;
        Some(self.off_to_u16(i))
    }
}

struct TextElement {
    input: Entity<TextInput>,
}
struct Prepaint {
    line: Option<ShapedLine>,
    cursor: Option<PaintQuad>,
}

impl IntoElement for TextElement {
    type Element = Self;
    fn into_element(self) -> Self {
        self
    }
}

impl Element for TextElement {
    type RequestLayoutState = ();
    type PrepaintState = Prepaint;
    fn id(&self) -> Option<ElementId> {
        None
    }
    fn source_location(&self) -> Option<&'static core::panic::Location<'static>> {
        None
    }
    fn request_layout(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&gpui::InspectorElementId>,
        window: &mut Window,
        cx: &mut App,
    ) -> (LayoutId, ()) {
        let mut style = Style::default();
        style.size.width = relative(1.).into();
        style.size.height = window.line_height().into();
        (window.request_layout(style, [], cx), ())
    }
    fn prepaint(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&gpui::InspectorElementId>,
        bounds: Bounds<Pixels>,
        _: &mut (),
        window: &mut Window,
        cx: &mut App,
    ) -> Prepaint {
        let inp = self.input.read(cx);
        let style = window.text_style();
        let (text, color) = if inp.content.is_empty() {
            (inp.placeholder.clone(), inp.hint)
        } else {
            (inp.content.clone(), inp.fg)
        };
        let mut font = style.font();
        font.family = inp.family.clone();
        let run = TextRun { len: text.len(), font, color, background_color: None, underline: None, strikethrough: None };
        let runs: Vec<TextRun> = if let Some(m) = inp.marked_range.as_ref().filter(|_| !inp.content.is_empty()) {
            [
                TextRun { len: m.start, ..run.clone() },
                TextRun {
                    len: m.end - m.start,
                    underline: Some(UnderlineStyle { color: Some(run.color), thickness: px(1.), wavy: false }),
                    ..run.clone()
                },
                TextRun { len: text.len() - m.end, ..run },
            ]
            .into_iter()
            .filter(|r| r.len > 0)
            .collect()
        } else {
            vec![run]
        };
        let fsz = style.font_size.to_pixels(window.rem_size());
        let line = window.text_system().shape_line(text, fsz, &runs, None);
        let x = line.x_for_index(if inp.content.is_empty() { 0 } else { inp.cursor });
        let cursor = fill(Bounds::new(point(bounds.left() + x, bounds.top()), size(px(2.), bounds.size.height)), inp.fg);
        Prepaint { line: Some(line), cursor: Some(cursor) }
    }
    fn paint(
        &mut self,
        _: Option<&GlobalElementId>,
        _: Option<&gpui::InspectorElementId>,
        bounds: Bounds<Pixels>,
        _: &mut (),
        pre: &mut Prepaint,
        window: &mut Window,
        cx: &mut App,
    ) {
        let fh = self.input.read(cx).focus_handle.clone();
        window.handle_input(&fh, ElementInputHandler::new(bounds, self.input.clone()), cx);
        let line = pre.line.take().unwrap();
        line.paint(bounds.origin, window.line_height(), gpui::TextAlign::Left, None, window, cx).unwrap();
        if fh.is_focused(window) {
            if let Some(c) = pre.cursor.take() {
                window.paint_quad(c);
            }
        }
        self.input.update(cx, |i, _| {
            i.last_layout = Some(line);
            i.last_bounds = Some(bounds);
        });
    }
}

impl Render for TextInput {
    fn render(&mut self, _: &mut Window, cx: &mut Context<Self>) -> impl IntoElement {
        div()
            .flex()
            .key_context("ProbeInput")
            .track_focus(&self.focus_handle(cx))
            .cursor(CursorStyle::IBeam)
            .on_action(cx.listener(Self::backspace))
            .on_action(cx.listener(Self::delete))
            .on_action(cx.listener(Self::left))
            .on_action(cx.listener(Self::right))
            .on_action(cx.listener(Self::home))
            .on_action(cx.listener(Self::end))
            .on_mouse_down(MouseButton::Left, cx.listener(Self::on_mouse_down))
            .child(div().w_full().h(px(28.)).px(px(8.)).py(px(4.)).rounded(px(6.)).bg(self.bg).child(TextElement { input: cx.entity() }))
    }
}

impl Focusable for TextInput {
    fn focus_handle(&self, _: &App) -> FocusHandle {
        self.focus_handle.clone()
    }
}
