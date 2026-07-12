import Foundation

/// Curated MG1 (PPC/Aurix) systems knowledge shown alongside a map's explanation: how the control
/// chain the map belongs to actually works, what usually limits it, and safe tuning practice.
///
/// Facts condensed (in our own words) from the public bootmod3 MG1 tuning guide and general MG1
/// platform knowledge; each article links the source for the full treatment. The S58 is an MG1
/// **Aurix** DME — the variant with the most limiters, and the one where the active limiter can be
/// datalogged via flag RAM channels.
public struct MG1KnowledgeArticle: Sendable, Equatable, Identifiable {
    public let id: String
    /// Short system title, e.g. "Boost control (PID + compressor map)".
    public let title: String
    /// How this part of MG1 works — the mental model needed to edit the map safely.
    public let howItWorks: String
    /// Practical, ordered guidance bullets.
    public let practice: [String]
    /// The sharp edge, if there is one.
    public let warning: String?
    /// Channels worth watching in the datalog while tuning this system (canonical S58 set).
    public let logChannels: [LogChannel]
    /// Source for the full guide.
    public let reference: URL

    /// Lowercased keywords matched against a table's name + subcategory (English and German).
    let keywords: [String]
    /// Categories the article may also claim when no keyword hits anywhere.
    let fallbackCategories: [CalibrationCategory]
}

/// Looks up the MG1 article for a table. Keyword match on name/subcategory wins; a category
/// fallback keeps coverage broad without misfiling specific maps.
public enum MG1TuningKnowledge {
    static let guideURL = URL(string: "https://bootmod3.atlassian.net/wiki/spaces/BCS/pages/3829268486")!

    public static func article(for definition: TableDefinition) -> MG1KnowledgeArticle? {
        let haystack = "\(definition.name) \(definition.subcategory ?? "")".lowercased()
        if let hit = articles.first(where: { $0.keywords.contains(where: haystack.contains) }) {
            return hit
        }
        return articles.first { $0.fallbackCategories.contains(definition.category) }
    }

    public static let articles: [MG1KnowledgeArticle] = [
        MG1KnowledgeArticle(
            id: "mg1.torque",
            title: "Torque-based control & torque limiters",
            howItWorks: """
            MG1 doesn't chase a boost number — it chases a torque target. Pedal input becomes a \
            torque request, the Optimal Reference Torque tables convert that torque into a load \
            target, and the load target then sets boost pressure, fuel mass and ignition timing \
            together. That's why the car makes the same power in different ambient conditions: the \
            DME just adjusts boost/timing until the torque target is met — and why raising boost \
            alone does nothing while a torque or load ceiling still binds.
            """,
            practice: [
                "Raise the Maximum Torque Limit tables (there can be up to five) gradually, logging a full pull between revisions.",
                "Scale Optimal Reference Torque correctly: raise the top load axis value and its column by the same percentage.",
                "Set the Full Load Torque Limitation variants high enough to never bind (800–1000 Nm is common practice).",
                "Remember the TCU's own cap (S58/N63T3/S63T4 ≈ 760 Nm) — beyond it you need a transmission flash.",
                "Work one limiter at a time: torque limit → clutch torque → load limiters, one datalog per change.",
            ],
            warning: "The torque *monitoring* tables are anti-tuning tripwires (stock ~3276 Nm). Making more power than stock without raising them can drop the car into limp mode.",
            logChannels: [.torque, .load, .rpm, .boost],
            reference: guideURL,
            keywords: ["torque", "moment", "clutch", "monitoring"],
            fallbackCategories: [.torque]
        ),

        MG1KnowledgeArticle(
            id: "mg1.load",
            title: "Load (relative filling) limiters",
            howItWorks: """
            "Relative filling" is MG1's load: cylinder filling as a percentage of a reference. A \
            family of setpoint tables caps it — a main maximum-filling characteristic plus variants \
            keyed to ignition-retard activity and to fuel quality (an adaptation value computed \
            from intake air temperature and octane via the Filling Reduction table). Whichever \
            ceiling is lowest wins, so power stays capped until *all* of the binding ones move.
            """,
            practice: [
                "Raise the main Maximum Relative Filling Characteristic first — many ROMs park several of these at 327%.",
                "On stock turbos, taper the load ceiling toward redline: a lower top-end boost target means less boost deviation.",
                "The fuel-quality variants take their axis from Filling Reduction (IAT & Octane) — hot intake air plus poor octane pulls load hard.",
                "S58/Aurix: datalog the Load Limit and Torque Limit (Flag) RAM channels — they tell you exactly which limiter is active (flag 4 = fuelling/LPFP).",
            ],
            warning: nil,
            logChannels: [.load, .rpm, .iat, .boost],
            reference: guideURL,
            keywords: ["filling", "füllung", "load limit", "load target", "relative filling"],
            fallbackCategories: []
        ),

        MG1KnowledgeArticle(
            id: "mg1.boost",
            title: "Boost control (compressor map + PID)",
            howItWorks: """
            There is no plain base-WGDC table. The DME computes required turbine power from a \
            compressor map (turbine mass flow × boost setpoint → kW) and turns it into a base \
            wastegate duty through the distribution factor — the split of exhaust gas sent through \
            the turbine versus out the wastegate. Higher factor = more energy to the turbine = \
            more boost. A PID trim rides on top of that base: P-gain reacts to boost deviation \
            (hPa), D-gain damps how fast spool is allowed to happen, I-gain removes steady-state \
            error, and floors/ceilings plus the PID Adder Ceiling bound the whole correction.
            """,
            practice: [
                "Fix the base before the trim: log WGDC (Base), Turbine Power, Distribution Factor and Target Mass Flow, and raise the compressor map's kW (and top mass-flow row) where the log shows it capping.",
                "Check the hidden setpoint limiters when boost tapers up top: Maximum Pressure Ratio (airflow/IAT-based) and Boost Setpoint Limitation (drops the setpoint at high airflow) both quietly cap the target.",
                "Tune P-gain by logging boost deviation at the target mass flow; use D-gain to slow an overshooting spool, I-gain only if steady boost still misses target (too much → wavy boost).",
                "Sport-mode boost offset pre-loads boost for throttle response; on a tuned map it can request more boost than the torque target wants and cause throttle closures — zeroing it fixes that.",
            ],
            warning: "Oversized PID bounds cause over/undershoot, and leaving the PID floor/ceiling stock at large deviations can throw the 120308 pressure-too-low plausibility fault. Excess base duty (especially with a high-flow downpipe) overboosts.",
            logChannels: [.boost, .wgdc, .rpm, .load],
            reference: guideURL,
            keywords: ["boost", "wgdc", "wastegate", "ladedruck", "pressure ratio", "compressor", "turbine", "pid", "i-factor", "p-gain", "d-gain", "i-gain"],
            fallbackCategories: [.boost]
        ),

        MG1KnowledgeArticle(
            id: "mg1.fuel",
            title: "Fuelling (lambda targets & scalars)",
            howItWorks: """
            Lambda targets exist per bank, with load axes extending far past what a stock car ever \
            reaches; the deep-load cells are very rich on purpose — thermal protection for when \
            load ends up there. A separate, even richer superknock target takes over after \
            misfire/superknock events. Global floors (Lambda Limit, Minimum Lambda) bound the \
            richest commanded mixture, and the Fuel Scalar / Correction Factor pair calibrates \
            injected mass for the actual fuel's stoichiometry.
            """,
            practice: [
                "Pumpgas targets in the tuned-load region: about λ0.84 on good fuel, λ0.82 or richer on low octane; ethanol blends tolerate leaner thanks to charge cooling — but watch HPFP headroom.",
                "Set Lambda Limit (floor) and Minimum Lambda to the richest point of your target tables so they agree.",
                "Leave the superknock lambda table stock — it's the safety net.",
                "Running ethanol blends, raise Fuel Scalar and Correction Factor together (~+5% for E30) and verify with logs: STFT should sit near 1.0 at idle and through a full pull.",
                "Load capped with limiter flag 4? That's the LPFP/fuelling limit chain — raise its flat load cap, and treat the high-value variants on G8x S58 ROMs with caution.",
            ],
            warning: "Chasing lean numbers on questionable fuel is how knock starts — richen first, verify, then lean back in steps.",
            logChannels: [.lambda, .fuelTrim, .load, .rpm],
            reference: guideURL,
            keywords: ["lambda", "fuel", "kraftstoff", "afr", "mixture", "scalar", "stft", "injection", "einspritz", "hpfp", "lpfp"],
            fallbackCategories: [.fuel]
        ),

        MG1KnowledgeArticle(
            id: "mg1.ignition",
            title: "Ignition timing (base, spool & corrections)",
            howItWorks: """
            Base Ignition Timing (Full Load – Warm) holds the pre-correction spark targets over \
            load and RPM. A separate spool table governs timing while boost is building — the \
            zone where extra boost most invites knock. Actual delivered timing is the base \
            reduced by a correction: an IAT-driven correction table scaled by its factor table.
            """,
            practice: [
                "When raising load/boost, start ~2° below stock at high load until logs show no corrections, then add timing back in small steps.",
                "Pull a couple of degrees in the spool region when running more boost than stock — then log; too much costs measurable power.",
                "Datalog every timing change: the target in the table only matters if the log shows the car following it without corrections.",
                "On ethanol blends, the IAT-based corrections can be relaxed — charge cooling does part of that work.",
            ],
            warning: "Timing is where MG1 hides the consequences of every other shortcut: knock retard showing up here usually means fuel quality or load targets need fixing first.",
            logChannels: [.ignitionTiming, .knock, .rpm, .load],
            reference: guideURL,
            keywords: ["ignition", "timing", "zünd", "spark", "spool", "knock", "klopf"],
            fallbackCategories: [.ignition]
        ),
    ]
}
