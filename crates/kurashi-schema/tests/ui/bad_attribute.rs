use kurashi_schema::KurashiSchema;

#[derive(KurashiSchema)]
struct Bar {
    /// Height
    #[kurashi(default = 32, colour = "red")]
    height: u32,
}

fn main() {}
