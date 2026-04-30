#![no_std]
extern crate alloc;

use alloc::format;
use alloc::string::String;
use packr_guest::{export, import, pack_types, GraphValue, Value};

packr_guest::setup_guest!();

#[derive(Clone, GraphValue)]
#[graph(crate = "packr_guest::composite_abi")]
pub struct ActorState {
    pub greeting: String,
    pub count: u32,
}

pack_types! {
    imports {
        theater:simple/runtime {
            log: func(msg: string),
        }
    }
    exports {
        theater:simple/actor.init: func(state: value) -> result<actor-state, string>,
        theater:hello/actions.greet: func(state: actor-state, name: string) -> result<tuple<actor-state, string>, string>,
    }
}

#[import(module = "theater:simple/runtime", name = "log")]
fn log(msg: String);

#[export(name = "theater:simple/actor.init")]
fn init(_state: Value) -> Result<(ActorState, ()), String> {
    log(String::from("[hello] init"));
    Ok((ActorState {
        greeting: String::from("Hello"),
        count: 0,
    }, ()))
}

#[export(name = "theater:hello/actions.greet")]
fn greet(state: ActorState, name: String) -> Result<(ActorState, String), String> {
    let message = format!("{}, {}!", state.greeting, name);
    log(format!("[hello] greet #{}: {}", state.count + 1, message));

    Ok((
        ActorState {
            count: state.count + 1,
            ..state
        },
        message,
    ))
}
