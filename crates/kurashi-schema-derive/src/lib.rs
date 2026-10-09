//! `#[derive(KurashiSchema)]`. The attribute reference lives in the `kurashi-schema` crate docs;
//! this crate only parses and expands. Everything checkable at compile time is checked here
//! (unknown attributes, malformed couplings, typed defaults/ranges); cross-key consistency is
//! checked by `Registry::build` at runtime.

use proc_macro::TokenStream;
use proc_macro2::TokenStream as Ts;
use quote::{format_ident, quote, quote_spanned};
use syn::spanned::Spanned;
use syn::{
    Attribute, Data, DeriveInput, Expr, ExprLit, Fields, Lit, LitInt, LitStr, Meta, RangeLimits,
    parse_macro_input,
};

const FIELD_ATTRS: &str = "default, range, step, unit, choices, choices_from, label, help, page, section, \
    per_output, requires, capability, overridden_by, restart, advanced, hidden, since, nested";
const CONTAINER_ATTRS: &str = "page, section, input_slots";
const SLOTS: &[&str] = &[
    "left",
    "right",
    "middle",
    "hover",
    "scroll_up",
    "scroll_down",
    "shift_scroll_up",
    "shift_scroll_down",
];

#[proc_macro_derive(KurashiSchema, attributes(kurashi))]
pub fn derive_kurashi_schema(input: TokenStream) -> TokenStream {
    let input = parse_macro_input!(input as DeriveInput);
    expand(&input)
        .unwrap_or_else(syn::Error::into_compile_error)
        .into()
}

fn expand(input: &DeriveInput) -> syn::Result<Ts> {
    if !input.generics.params.is_empty() {
        return Err(syn::Error::new(
            input.generics.span(),
            "KurashiSchema types cannot be generic",
        ));
    }
    match &input.data {
        Data::Struct(s) => match &s.fields {
            Fields::Named(_) => expand_struct(input, &s.fields),
            _ => Err(syn::Error::new(
                input.ident.span(),
                "KurashiSchema structs need named fields",
            )),
        },
        Data::Enum(e) => expand_enum(input, e),
        Data::Union(_) => Err(syn::Error::new(
            input.ident.span(),
            "KurashiSchema does not support unions",
        )),
    }
}

// ---------------------------------------------------------------------------------------------
// Attribute parsing

#[derive(Default)]
struct FieldAttrs {
    default: Option<Expr>,
    range: Option<(Expr, Expr)>,
    step: Option<Expr>,
    unit: Option<LitStr>,
    choices: Option<Vec<LitStr>>,
    choices_from: Option<LitStr>,
    label: Option<LitStr>,
    help: Option<LitStr>,
    page: Option<LitStr>,
    section: Option<LitStr>,
    per_output: bool,
    restart: bool,
    advanced: bool,
    hidden: bool,
    nested: bool,
    requires: Vec<(String, bool, String)>,
    capability: Vec<LitStr>,
    overridden_by: Vec<(String, Option<String>)>,
    since: Option<LitInt>,
    /// Span of every attribute that only makes sense on a leaf (for the `nested` check).
    leaf_only: Vec<(proc_macro2::Span, &'static str)>,
}

#[derive(Default)]
struct ContainerAttrs {
    page: Option<LitStr>,
    section: Option<LitStr>,
    input_slots: Vec<(String, LitStr)>,
}

fn set_once<T>(slot: &mut Option<T>, v: T, span: proc_macro2::Span, name: &str) -> syn::Result<()> {
    if slot.is_some() {
        return Err(syn::Error::new(
            span,
            format!("duplicate `{name}` attribute"),
        ));
    }
    *slot = Some(v);
    Ok(())
}

fn parse_field_attrs(attrs: &[Attribute]) -> syn::Result<FieldAttrs> {
    let mut a = FieldAttrs::default();
    for attr in attrs.iter().filter(|a| a.path().is_ident("kurashi")) {
        attr.parse_nested_meta(|meta| {
            let span = meta.path.span();
            let name = meta
                .path
                .get_ident()
                .map(ToString::to_string)
                .unwrap_or_default();
            let leaf_only = |a: &mut FieldAttrs, n: &'static str| a.leaf_only.push((span, n));
            match name.as_str() {
                "default" => {
                    leaf_only(&mut a, "default");
                    set_once(&mut a.default, meta.value()?.parse()?, span, "default")?;
                }
                "range" => {
                    leaf_only(&mut a, "range");
                    let e: Expr = meta.value()?.parse()?;
                    let range = match &e {
                        Expr::Range(r) if matches!(r.limits, RangeLimits::Closed(_)) => {
                            match (&r.start, &r.end) {
                                (Some(lo), Some(hi)) => Some(((**lo).clone(), (**hi).clone())),
                                _ => None,
                            }
                        }
                        _ => None,
                    };
                    let range = range.ok_or_else(|| {
                        syn::Error::new(e.span(), "`range` must be an inclusive range `a..=b`")
                    })?;
                    set_once(&mut a.range, range, span, "range")?;
                }
                "step" => {
                    leaf_only(&mut a, "step");
                    set_once(&mut a.step, meta.value()?.parse()?, span, "step")?;
                }
                "unit" => {
                    leaf_only(&mut a, "unit");
                    set_once(&mut a.unit, meta.value()?.parse()?, span, "unit")?;
                }
                "choices" => {
                    leaf_only(&mut a, "choices");
                    let arr: syn::ExprArray = meta.value()?.parse()?;
                    let mut items = Vec::new();
                    for e in arr.elems {
                        match e {
                            Expr::Lit(ExprLit {
                                lit: Lit::Str(s), ..
                            }) => items.push(s),
                            other => {
                                return Err(syn::Error::new(
                                    other.span(),
                                    "`choices` must be a list of string literals",
                                ));
                            }
                        }
                    }
                    if items.is_empty() {
                        return Err(meta.error("`choices` must not be empty"));
                    }
                    set_once(&mut a.choices, items, span, "choices")?;
                }
                "choices_from" => {
                    leaf_only(&mut a, "choices_from");
                    let src: LitStr = meta.value()?.parse()?;
                    if src.value().is_empty() {
                        return Err(syn::Error::new(
                            src.span(),
                            "`choices_from` must name a source",
                        ));
                    }
                    set_once(&mut a.choices_from, src, span, "choices_from")?;
                }
                "label" => {
                    leaf_only(&mut a, "label");
                    set_once(&mut a.label, meta.value()?.parse()?, span, "label")?;
                }
                "help" => {
                    leaf_only(&mut a, "help");
                    set_once(&mut a.help, meta.value()?.parse()?, span, "help")?;
                }
                "page" => set_once(&mut a.page, meta.value()?.parse()?, span, "page")?,
                "section" => set_once(&mut a.section, meta.value()?.parse()?, span, "section")?,
                "per_output" | "restart" | "advanced" | "hidden" => {
                    let flag = match name.as_str() {
                        "per_output" => (&mut a.per_output, "per_output"),
                        "restart" => (&mut a.restart, "restart"),
                        "advanced" => (&mut a.advanced, "advanced"),
                        _ => (&mut a.hidden, "hidden"),
                    };
                    *flag.0 = true;
                    let n = flag.1;
                    leaf_only(&mut a, n);
                }
                "nested" => a.nested = true,
                "since" => {
                    leaf_only(&mut a, "since");
                    let lit: LitInt = meta.value()?.parse()?;
                    lit.base10_parse::<u32>()?;
                    set_once(&mut a.since, lit, span, "since")?;
                }
                "capability" => {
                    leaf_only(&mut a, "capability");
                    let lit: LitStr = meta.value()?.parse()?;
                    if !is_ident_like(&lit.value()) {
                        return Err(syn::Error::new(
                            lit.span(),
                            "capability names are lowercase words like `blur`",
                        ));
                    }
                    a.capability.push(lit);
                }
                "requires" => {
                    leaf_only(&mut a, "requires");
                    let lit: LitStr = meta.value()?.parse()?;
                    let parsed = parse_requires(&lit.value())
                        .map_err(|msg| syn::Error::new(lit.span(), msg))?;
                    a.requires.push(parsed);
                }
                "overridden_by" => {
                    leaf_only(&mut a, "overridden_by");
                    let lit: LitStr = meta.value()?.parse()?;
                    let parsed = parse_overridden_by(&lit.value())
                        .map_err(|msg| syn::Error::new(lit.span(), msg))?;
                    a.overridden_by.push(parsed);
                }
                _ => {
                    return Err(meta.error(format!(
                        "unknown kurashi attribute `{name}`; expected one of: {FIELD_ATTRS}"
                    )));
                }
            }
            Ok(())
        })?;
    }
    Ok(a)
}

fn parse_container_attrs(attrs: &[Attribute]) -> syn::Result<ContainerAttrs> {
    let mut a = ContainerAttrs::default();
    for attr in attrs.iter().filter(|a| a.path().is_ident("kurashi")) {
        attr.parse_nested_meta(|meta| {
            let span = meta.path.span();
            if meta.path.is_ident("page") {
                set_once(&mut a.page, meta.value()?.parse()?, span, "page")
            } else if meta.path.is_ident("section") {
                set_once(&mut a.section, meta.value()?.parse()?, span, "section")
            } else if meta.path.is_ident("input_slots") {
                meta.parse_nested_meta(|slot| {
                    let name = slot
                        .path
                        .get_ident()
                        .map(ToString::to_string)
                        .unwrap_or_default();
                    if !SLOTS.contains(&name.as_str()) {
                        return Err(slot.error(format!(
                            "unknown input slot `{name}`; expected one of: {}",
                            SLOTS.join(", ")
                        )));
                    }
                    if a.input_slots.iter().any(|(s, _)| *s == name) {
                        return Err(slot.error(format!("duplicate input slot `{name}`")));
                    }
                    let action: LitStr = slot.value()?.parse()?;
                    if !is_dotted(&action.value()) {
                        return Err(syn::Error::new(
                            action.span(),
                            "action ids are dotted lowercase words like `island.expand`",
                        ));
                    }
                    a.input_slots.push((name, action));
                    Ok(())
                })
            } else {
                Err(meta.error(format!(
                    "unknown kurashi container attribute; expected one of: {CONTAINER_ATTRS}"
                )))
            }
        })?;
    }
    Ok(a)
}

/// English label (first doc line) and help (the rest) from `///` comments.
fn doc_text(attrs: &[Attribute]) -> (Option<String>, Option<String>) {
    let mut lines = Vec::new();
    for attr in attrs.iter().filter(|a| a.path().is_ident("doc")) {
        if let Meta::NameValue(nv) = &attr.meta
            && let Expr::Lit(ExprLit {
                lit: Lit::Str(s), ..
            }) = &nv.value
        {
            lines.extend(s.value().lines().map(|l| l.trim().to_owned()));
        }
    }
    let mut it = lines.into_iter().skip_while(String::is_empty);
    let label = it.next();
    let help: Vec<String> = it.filter(|l| !l.is_empty()).collect();
    (label, (!help.is_empty()).then(|| help.join(" ")))
}

fn is_ident_like(s: &str) -> bool {
    !s.is_empty()
        && s.starts_with(|c: char| c.is_ascii_lowercase())
        && s.bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit() || b == b'_' || b == b'-')
}

fn is_dotted(s: &str) -> bool {
    s.split('.').all(is_ident_like)
}

/// `"<key> == <value>"` / `"<key> != <value>"` → (key, ne, canonical JSON).
fn parse_requires(s: &str) -> Result<(String, bool, String), String> {
    let (key, ne, rhs) = if let Some((k, v)) = s.split_once("!=") {
        (k, true, v)
    } else if let Some((k, v)) = s.split_once("==") {
        (k, false, v)
    } else {
        return Err(format!(
            "`requires` must look like \"<key> == <value>\" or \"<key> != <value>\", got {s:?}"
        ));
    };
    let key = key.trim();
    if !is_dotted(key) {
        return Err(format!("`requires`: {key:?} is not a dotted config key"));
    }
    Ok((key.to_owned(), ne, json_value(rhs)?))
}

/// `"<key>"` / `"<key> => <value>"` → (key, forced JSON).
fn parse_overridden_by(s: &str) -> Result<(String, Option<String>), String> {
    let (key, forces) = match s.split_once("=>") {
        Some((k, v)) => (k.trim(), Some(json_value(v)?)),
        None => (s.trim(), None),
    };
    if !is_dotted(key) {
        return Err(format!(
            "`overridden_by`: {key:?} is not a dotted config key (\"<key>\" or \"<key> => <value>\")"
        ));
    }
    Ok((key.to_owned(), forces))
}

/// JSON literal, or a bare word meaning a string.
fn json_value(src: &str) -> Result<String, String> {
    let src = src.trim();
    match serde_json::from_str::<serde_json::Value>(src) {
        Ok(v) => Ok(v.to_string()),
        Err(_) if is_ident_like(src) => Ok(serde_json::Value::from(src).to_string()),
        Err(e) => Err(format!("{src:?} is neither JSON nor a bare word: {e}")),
    }
}

fn snake_case(ident: &str) -> String {
    let mut out = String::new();
    for (i, c) in ident.chars().enumerate() {
        if c.is_uppercase() {
            if i > 0 {
                out.push('_');
            }
            out.extend(c.to_lowercase());
        } else {
            out.push(c);
        }
    }
    out
}

fn humanize(id: &str) -> String {
    let s = id.replace(['_', '-'], " ");
    let mut c = s.chars();
    match c.next() {
        Some(f) => f.to_uppercase().chain(c).collect(),
        None => String::new(),
    }
}

fn opt_str(v: &Option<LitStr>) -> Ts {
    match v {
        Some(s) => quote!(::core::option::Option::Some(#s)),
        None => quote!(::core::option::Option::None),
    }
}

// ---------------------------------------------------------------------------------------------
// Structs → KurashiNode

fn expand_struct(input: &DeriveInput, fields: &Fields) -> syn::Result<Ts> {
    let name = &input.ident;
    let c = parse_container_attrs(&input.attrs)?;
    let cpage = opt_str(&c.page);
    let csection = opt_str(&c.section);

    let mut collect = Vec::new();
    let mut init = Vec::new();
    // One function per leaf default so the expression is type-checked (and errors) once.
    let mut default_fns = Vec::new();
    for field in fields {
        let ident = field.ident.as_ref().expect("named fields");
        let key = ident.to_string().trim_start_matches("r#").to_owned();
        let ty = &field.ty;
        let a = parse_field_attrs(&field.attrs)?;
        let fpage = opt_str(&a.page);
        let fsection = opt_str(&a.section);

        if a.nested {
            if let Some((span, attr)) = a.leaf_only.first() {
                return Err(syn::Error::new(
                    *span,
                    format!("`{attr}` does not apply to a `nested` table (only page/section do)"),
                ));
            }
            collect.push(quote! {
                <#ty as ::kurashi_schema::KurashiNode>::collect(
                    &::kurashi_schema::__private::join(__prefix, #key),
                    &__ctx.with(#fpage, #fsection),
                    __out,
                );
            });
            init.push(quote!(#ident: <#ty as ::kurashi_schema::KurashiNode>::schema_default()));
            continue;
        }

        let default = a.default.as_ref().ok_or_else(|| {
            syn::Error::new(
                ident.span(),
                format!(
                    "config key `{key}` needs `#[kurashi(default = ...)]` \
                     (or `#[kurashi(nested)]` if it is a sub-table)"
                ),
            )
        })?;
        let default_fn = format_ident!("__kurashi_default_{}", key);
        let (label_en, help_en) = doc_text(&field.attrs);
        let label_en = label_en.ok_or_else(|| {
            syn::Error::new(
                ident.span(),
                format!(
                    "config key `{key}` needs a doc comment (first line = English label, \
                     rest = help)"
                ),
            )
        })?;
        let help_en = match &help_en {
            Some(h) => quote!(::core::option::Option::Some(#h)),
            None => quote!(::core::option::Option::None),
        };

        let mut body = Vec::new();
        if let Some((lo, hi)) = &a.range {
            body.push(quote_spanned! {lo.span()=>
                ::kurashi_schema::__private::assert_numeric::<#ty>();
                let __lo: #ty = #lo;
                let __hi: #ty = #hi;
                __m.constraints.min = ::core::option::Option::Some(::kurashi_schema::__private::value(&__lo));
                __m.constraints.max = ::core::option::Option::Some(::kurashi_schema::__private::value(&__hi));
            });
        }
        if let Some(step) = &a.step {
            body.push(quote_spanned! {step.span()=>
                ::kurashi_schema::__private::assert_numeric::<#ty>();
                let __step: #ty = #step;
                __m.constraints.step = ::core::option::Option::Some(::kurashi_schema::__private::value(&__step));
            });
        }
        if let Some(unit) = &a.unit {
            body.push(
                quote!(__m.constraints.unit = ::core::option::Option::Some(#unit.to_owned());),
            );
        }
        if let Some(choices) = &a.choices {
            let pairs = choices.iter().map(|s| {
                let text = humanize(&s.value());
                quote!((#s, #text))
            });
            let span = choices[0].span();
            body.push(quote_spanned! {span=>
                ::kurashi_schema::__private::assert_textual::<#ty>();
                __m.constraints.choices =
                    ::kurashi_schema::__private::string_choices(&__m.key, &[#(#pairs),*]);
            });
        }
        if let Some(src) = &a.choices_from {
            if let Some(c) = &a.choices {
                return Err(syn::Error::new(
                    c[0].span(),
                    "use either `choices` or `choices_from`, not both",
                ));
            }
            body.push(quote_spanned! {src.span()=>
                ::kurashi_schema::__private::assert_choice_source::<#ty>();
                __m.constraints.choices_from = ::core::option::Option::Some(#src.to_owned());
            });
        }
        if let Some(label) = &a.label {
            body.push(quote!(__m.label = #label.to_owned();));
        }
        if let Some(help) = &a.help {
            body.push(quote!(__m.help = ::core::option::Option::Some(#help.to_owned());));
        }
        for (flag, on) in [
            ("per_output", a.per_output),
            ("restart", a.restart),
            ("advanced", a.advanced),
            ("hidden", a.hidden),
        ] {
            if on {
                let f = format_ident!("{flag}");
                body.push(quote!(__m.flags.#f = true;));
            }
        }
        for (key, ne, json) in &a.requires {
            body.push(quote! {
                __m.couplings.push(::kurashi_schema::__private::requires(#key, #ne, #json));
            });
        }
        for cap in &a.capability {
            body.push(quote!(__m.couplings.push(::kurashi_schema::__private::capability(#cap));));
        }
        for (key, forces) in &a.overridden_by {
            let forces = match forces {
                Some(f) => quote!(::core::option::Option::Some(#f)),
                None => quote!(::core::option::Option::None),
            };
            body.push(quote! {
                __m.couplings.push(::kurashi_schema::__private::overridden_by(#key, #forces));
            });
        }
        if let Some(since) = &a.since {
            body.push(quote!(__m.since = #since;));
        }

        collect.push(quote! {
            {
                let __default: #ty = Self::#default_fn();
                #[allow(unused_mut)]
                let mut __m = ::kurashi_schema::__private::leaf::<#ty>(
                    __prefix, #key, &__ctx.with(#fpage, #fsection), &__default, #label_en, #help_en,
                );
                #(#body)*
                __out.push(__m);
            }
        });
        default_fns.push(quote! {
            #[doc(hidden)]
            #[allow(non_snake_case)]
            fn #default_fn() -> #ty {
                #default
            }
        });
        init.push(quote!(#ident: Self::#default_fn()));
    }

    let slots = if c.input_slots.is_empty() {
        quote!()
    } else {
        let pairs = c.input_slots.iter().map(|(s, a)| quote!((#s, #a)));
        quote! {
            ::kurashi_schema::__private::input_slots(__prefix, &__ctx, &[#(#pairs),*], __out);
        }
    };

    Ok(quote! {
        impl #name {
            #(#default_fns)*
        }

        impl ::kurashi_schema::KurashiNode for #name {
            fn collect(
                __prefix: &str,
                __ctx: &::kurashi_schema::Ctx,
                __out: &mut ::std::vec::Vec<::kurashi_schema::KeyMeta>,
            ) {
                let __ctx = __ctx.with(#cpage, #csection);
                #(#collect)*
                #slots
            }

            fn schema_default() -> Self {
                Self { #(#init),* }
            }
        }
    })
}

// ---------------------------------------------------------------------------------------------
// Unit enums → KurashiLeaf (choices)

fn expand_enum(input: &DeriveInput, data: &syn::DataEnum) -> syn::Result<Ts> {
    let name = &input.ident;
    let mut i18n: Option<LitStr> = None;
    for attr in input.attrs.iter().filter(|a| a.path().is_ident("kurashi")) {
        attr.parse_nested_meta(|meta| {
            if meta.path.is_ident("i18n") {
                set_once(&mut i18n, meta.value()?.parse()?, meta.path.span(), "i18n")
            } else {
                Err(meta.error("unknown kurashi enum attribute; expected: i18n"))
            }
        })?;
    }
    let id = i18n.map_or_else(|| snake_case(&name.to_string()), |l| l.value());
    if data.variants.is_empty() {
        return Err(syn::Error::new(
            name.span(),
            "KurashiSchema enums need variants",
        ));
    }

    let mut arms = Vec::new();
    let mut choices = Vec::new();
    for v in &data.variants {
        if !matches!(v.fields, Fields::Unit) {
            return Err(syn::Error::new(
                v.span(),
                "KurashiSchema enums are choices: only unit variants are allowed",
            ));
        }
        let mut rename: Option<LitStr> = None;
        for attr in v.attrs.iter().filter(|a| a.path().is_ident("kurashi")) {
            attr.parse_nested_meta(|meta| {
                if meta.path.is_ident("rename") {
                    set_once(
                        &mut rename,
                        meta.value()?.parse()?,
                        meta.path.span(),
                        "rename",
                    )
                } else {
                    Err(meta.error("unknown kurashi variant attribute; expected: rename"))
                }
            })?;
        }
        let ident = &v.ident;
        let value = rename.map_or_else(|| snake_case(&ident.to_string()), |l| l.value());
        let text = doc_text(&v.attrs).0.unwrap_or_else(|| humanize(&value));
        let label = format!("config.choice.{id}.{value}");
        arms.push(quote!(Self::#ident => #value));
        choices.push(quote! {
            ::kurashi_schema::Choice {
                value: #value.to_owned(),
                label: #label.to_owned(),
                text: #text.to_owned(),
            }
        });
    }

    Ok(quote! {
        impl ::kurashi_schema::KurashiLeaf for #name {
            fn ty() -> ::kurashi_schema::Ty {
                ::kurashi_schema::Ty::Choice
            }
            fn to_value(&self) -> ::kurashi_schema::__private::JsonValue {
                let s: &str = match self { #(#arms),* };
                ::kurashi_schema::__private::JsonValue::String(s.to_owned())
            }
            fn choices() -> ::std::vec::Vec<::kurashi_schema::Choice> {
                ::std::vec![#(#choices),*]
            }
        }
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn requires_forms() {
        assert_eq!(
            parse_requires("theme.material.kind != solid").unwrap(),
            ("theme.material.kind".into(), true, "\"solid\"".into())
        );
        assert_eq!(
            parse_requires("a.b == 3").unwrap(),
            ("a.b".into(), false, "3".into())
        );
        assert!(parse_requires("a.b = 3").is_err());
        assert!(parse_requires("A B == 3").is_err());
        assert!(parse_requires("a.b == not json!").is_err());
    }

    #[test]
    fn overridden_by_forms() {
        assert_eq!(
            parse_overridden_by("a11y.reduce_motion => none").unwrap(),
            ("a11y.reduce_motion".into(), Some("\"none\"".into()))
        );
        assert_eq!(
            parse_overridden_by("a11y.large_text").unwrap(),
            ("a11y.large_text".into(), None)
        );
    }

    #[test]
    fn names() {
        assert_eq!(snake_case("MotionProfile"), "motion_profile");
        assert_eq!(snake_case("None"), "none");
        assert_eq!(humanize("scroll_up"), "Scroll up");
    }
}
