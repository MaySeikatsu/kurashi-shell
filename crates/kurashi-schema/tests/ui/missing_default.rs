use kurashi_schema::KurashiSchema;

#[derive(KurashiSchema)]
struct Bar {
    /// Height
    #[kurashi(per_output)]
    height: u32,
}

fn main() {}
