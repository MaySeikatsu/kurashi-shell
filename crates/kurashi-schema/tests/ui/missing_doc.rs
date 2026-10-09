use kurashi_schema::KurashiSchema;

#[derive(KurashiSchema)]
struct Bar {
    #[kurashi(default = 32)]
    height: u32,
}

fn main() {}
