use kurashi_schema::KurashiSchema;

#[derive(KurashiSchema)]
struct Bar {
    /// Shown
    #[kurashi(default = true, range = false..=true)]
    shown: bool,
}

fn main() {}
