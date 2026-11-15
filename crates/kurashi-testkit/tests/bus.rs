//! The helpers themselves: a started bus answers a client, a bus restarted at the same address is reached
//! there again, and a scratch directory goes with its owner.

use kurashi_testkit::{Scratch, TestBus};

#[tokio::test]
async fn a_started_bus_gives_a_client_a_name() {
    let bus = TestBus::start();
    let conn = bus.conn().await;
    assert!(conn.unique_name().is_some(), "the daemon names the client");
}

#[tokio::test]
async fn a_bus_restarted_at_its_address_is_reached_there() {
    let scratch = Scratch::new("restart");
    let mut bus = TestBus::start_in(&scratch);
    assert!(bus.addr().starts_with(&scratch.bus_addr()));
    bus.kill();
    let bus = TestBus::start_in(&scratch);
    assert!(bus.conn().await.unique_name().is_some());
}

#[test]
fn a_scratch_directory_goes_with_its_owner() {
    let scratch = Scratch::new("owner");
    let path = scratch.path().to_owned();
    assert!(path.is_dir());
    drop(scratch);
    assert!(!path.exists());
}
