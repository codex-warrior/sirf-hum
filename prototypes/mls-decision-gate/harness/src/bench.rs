//! Rough timings for the decision gate (Prompt 05 §23). Not a rigorous
//! benchmark: single-threaded, wall clock, medians of small samples, on a
//! CI runner. Use only to compare the two backends on the same machine.

#[cfg(not(target_arch = "wasm32"))]
pub fn run<B: crate::Backend>() {
    use std::time::{Duration, Instant};

    fn median(mut samples: Vec<Duration>) -> f64 {
        samples.sort();
        samples[samples.len() / 2].as_secs_f64() * 1e6
    }

    const N: usize = 30;
    let mut rows: Vec<(String, f64)> = vec![];

    // Group creation.
    let creator = B::new_device("a/1");
    rows.push(("create group".into(), median((0..N).map(|_| {
        let t = Instant::now();
        let _g = B::create_group(&creator);
        t.elapsed()
    }).collect())));

    // Add one member (commit + local merge) and join from the Welcome.
    let (mut add, mut join) = (vec![], vec![]);
    for _ in 0..N {
        let mut g = B::create_group(&creator);
        let d = B::new_device("b/1");
        let kp = B::key_package(&d);
        let t = Instant::now();
        let (_c, w) = B::add(&creator, &mut g, &[kp]);
        add.push(t.elapsed());
        let t = Instant::now();
        let _bg = B::join(&d, &w);
        join.push(t.elapsed());
    }
    rows.push(("add member (commit)".into(), median(add)));
    rows.push(("join from welcome".into(), median(join)));

    // Remove one member from a 3-device group.
    let mut remove = vec![];
    for _ in 0..N {
        let mut g = B::create_group(&creator);
        let kps: Vec<_> = ["b/1", "b/2"].iter().map(|l| B::key_package(&B::new_device(l))).collect();
        let _ = B::add(&creator, &mut g, &kps);
        let t = Instant::now();
        let _c = B::remove(&creator, &mut g, "b/2");
        remove.push(t.elapsed());
    }
    rows.push(("remove member (commit)".into(), median(remove)));

    // Encrypt / decrypt at representative sizes.
    let mut g = B::create_group(&creator);
    let reader = B::new_device("b/1");
    let (_c, w) = B::add(&creator, &mut g, &[B::key_package(&reader)]);
    let mut rg = B::join(&reader, &w);
    for size in [1024usize, 10 * 1024, 100 * 1024] {
        let payload = vec![0x5a; size];
        let (mut enc, mut dec) = (vec![], vec![]);
        for _ in 0..N {
            let t = Instant::now();
            let ct = B::encrypt(&creator, &mut g, &payload);
            enc.push(t.elapsed());
            let t = Instant::now();
            let pt = B::decrypt(&reader, &mut rg, &ct).expect("decrypt");
            dec.push(t.elapsed());
            assert_eq!(pt.len(), size);
        }
        rows.push((format!("encrypt {} KB", size / 1024), median(enc)));
        rows.push((format!("decrypt {} KB", size / 1024), median(dec)));
    }

    // State serialization and restoration.
    let (mut ser, mut res, mut bytes) = (vec![], vec![], 0usize);
    for _ in 0..N {
        let t = Instant::now();
        let snap = B::snapshot(&reader, &mut rg);
        ser.push(t.elapsed());
        bytes = snap.len();
        let t = Instant::now();
        let _restored = B::restore(&snap);
        res.push(t.elapsed());
    }
    rows.push(("serialize state".into(), median(ser)));
    rows.push(("restore state".into(), median(res)));

    println!("BENCH {} (median of {N}, microseconds)", B::NAME);
    for (name, us) in rows {
        println!("BENCH {} | {name} | {us:.0}", B::NAME);
    }
    println!("BENCH {} | snapshot size bytes | {bytes}", B::NAME);
}
