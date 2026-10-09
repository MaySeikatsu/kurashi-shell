use kurashi_schema::KurashiSchema;

#[derive(KurashiSchema)]
struct Bar {
    /// Height
    #[kurashi(default = "tall", range = 16..=96)]
    height: u32,
}

fn main() {}
