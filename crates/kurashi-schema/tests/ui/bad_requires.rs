use kurashi_schema::KurashiSchema;

#[derive(KurashiSchema)]
struct Bar {
    /// Height
    #[kurashi(default = 32, requires = "bar.enabled = true")]
    height: u32,
}

fn main() {}
