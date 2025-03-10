;; 954e495695af05d9a3afb8b8fb3e6d2719b1d1b23b8219804e2b37269b88a895
;; aibtc.com DAO faktory.fun PRE @version 1.0
;; Pre-launch contract for token distribution
;; Dynamic allocation: 1-7 seats per user in Period 1
;; Each seat = 7.5 STX, targeting 20 seats total with minimum 10 users

(use-trait faktory-token .faktory-trait-v1.sip-010-trait) ;; 'STTWD9SPRQVD3P733V89SV0P8RZRZNQADG034F0A

(define-constant SEATS u20)
(define-constant MIN-USERS u10)
(define-constant MAX-SEATS-PER-USER u7)
(define-constant PRICE-PER-SEAT u7500000) ;; 7.5 STX in microSTX
(define-constant TOKENS-PER-SEAT u2000000000000) ;; 2M tokens per seat if supply 1B
(define-constant EXPIRATION-PERIOD u2100) ;; 1 Stacks reward cycle in PoX-4
(define-constant PERIOD-2-LENGTH u100) ;; blocks for redistribution period

(define-constant FT-INITIALIZED-BALANCE u40000000000000) ;; 40M tokens for pre-launch if supply 1B
(define-constant ACCELERATED-PERCENT u60) 

;; Vesting schedule (percentages add up to 100)
(define-constant VESTING-SCHEDULE
    (list 
        {height: u100, percent: u10, id: u0}  ;; 10% at start
        {height: u1000, percent: u20, id: u1}  ;; 20% more
        {height: u2100, percent: u30, id: u2}  ;; 30% more
        {height: u4200, percent: u40, id: u3})) ;; Final 40%

(define-constant MULTI-SIG-CREATOR tx-sender) ;; if a multi-sig can create a multi-sig then this is a multi-sig 2 of 5

;; Data vars
(define-data-var ft-balance uint u0)
(define-data-var stx-balance uint u0)
(define-data-var total-seats-taken uint u0)
(define-data-var total-users uint u0)
(define-data-var token-contract (optional principal) none)
(define-data-var distribution-height (optional uint) none)
(define-data-var deployment-height (optional uint) none)
(define-data-var period-2-height (optional uint) none)
(define-data-var accelerated-vesting bool false)

;; Determined after multi-sig creation
(define-data-var dao-token (optional principal) none) ;; 'STRZ4P1ABSVSZPC4HZ4GDAW834HHEHJMF65X5S6D.txt6-faktory)
(define-data-var dex-contract (optional principal) none) ;; 'STRZ4P1ABSVSZPC4HZ4GDAW834HHEHJMF65X5S6D.txt6-faktory-dex)
(define-data-var dao-multi-sig (optional principal) none) ;; 'ST3SPSJDYGHF0ARGV1TNS0HX6JEP7T1J6849A7BB4)
;; Helper vars
(define-data-var target-owner principal 'STTWD9SPRQVD3P733V89SV0P8RZRZNQADG034F0A) ;; cant-be-evil.stx  in testnet? random 'SP000000000000000000002Q6VF78

;; Define a data variable to track seat holders
(define-data-var seat-holders (list 20 {owner: principal, seats: uint}) (list))

;; Track seat ownership and claims
(define-map seats-owned principal uint)
(define-map claimed-amounts principal uint)

;; Error constants
(define-constant ERR-TOO-MANY-SEATS (err u300))
(define-constant ERR-NO-SEATS-LEFT (err u301))
(define-constant ERR-NOT-SEAT-OWNER (err u302))
(define-constant ERR-NOT-SET (err u303))
(define-constant ERR-NOTHING-TO-CLAIM (err u304))
(define-constant ERR-NOT-AUTHORIZED (err u305))
(define-constant ERR-ALREADY-INITIALIZED (err u306))
(define-constant ERR-WRONG-TOKEN (err u307))
(define-constant ERR-ALREADY-EXPIRED (err u308))
(define-constant ERR-NOT-EXPIRED (err u309))
(define-constant ERR-NO-REFUND (err u310))
(define-constant ERR-CONTRACT-INSUFFICIENT-FUNDS (err u311))
(define-constant ERR-PERIOD-2-MULTIPLE-SEATS (err u312))
(define-constant ERR-INVALID-SEAT-COUNT (err u313))
(define-constant ERR-SLICE-FAILED (err u314))
(define-constant ERR-TOO-LONG (err u315))
(define-constant ERR-REMOVING-HOLDER (err u316))
(define-constant ERR-HIGHEST-ONE-SEAT (err u317))
(define-constant ERR-NOT-BONDED (err u318))
(define-constant ERR-PERIOD-2-NOT-INITIALIZED (err u319))
(define-constant ERR-PERIOD-2-ALREADY-STARTED (err u320))
(define-constant ERR-DISTRIBUTION-NOT-INITIALIZED (err u321))
(define-constant ERR-HIGHEST-HOLDER (err u322))


;; Helper functions for period management
(define-private (is-period-1-expired)
    (match (var-get deployment-height)
        start-height (>= burn-block-height (+ start-height EXPIRATION-PERIOD))
        false))

(define-private (is-in-period-2)
    (match (var-get period-2-height)
        start-height (< burn-block-height (+ start-height PERIOD-2-LENGTH))
        false))

;; Helper function to update seat holders list
(define-private (update-seat-holder (owner principal) (seat-count uint))
  (let ((current-holders (var-get seat-holders))
        (updated-list (update-or-add-holder current-holders owner seat-count)))
    (var-set seat-holders updated-list)))

;; Helper to update or add a holder to the list
(define-private (update-or-add-holder 
    (holders (list 20 {owner: principal, seats: uint}))
    (owner principal)
    (seat-count uint))
  (let ((position (find-holder-position holders owner)))
    (if (is-some position)
        ;; Update existing holder - unwrap the optional result
        (unwrap-panic (replace-at? holders (unwrap-panic position) {owner: owner, seats: seat-count}))
        ;; Add new holder
        (unwrap-panic (as-max-len? (append holders {owner: owner, seats: seat-count}) u20)))))

;; Helper to find a holder's position in the list
(define-private (find-holder-position 
    (holders (list 20 {owner: principal, seats: uint}))
    (owner principal))
  (let ((result (fold check-if-owner 
                     holders 
                     {found: false, index: u0, current: u0})))
    (var-set target-owner owner)
    (if (get found result)
        (some (get index result))
        none)))

(define-private (check-if-owner 
    (entry {owner: principal, seats: uint}) 
    (state {found: bool, index: uint, current: uint}))
  (if (get found state)
      ;; Already found, just pass through
      state
      ;; Check if this is the owner we're looking for
      (if (is-eq (get owner entry) (var-get target-owner))
          ;; Found it, update state
          {found: true, index: (get current state), current: (+ (get current state) u1)}
          ;; Not found, increment counter
          {found: false, index: (get index state), current: (+ (get current state) u1)})))

(define-private (remove-seat-holder (holder principal))
  (let ((position (find-holder-position (var-get seat-holders) holder))
        (current-list (var-get seat-holders)))
    (match position 
        pos (let ((before-slice (unwrap! (slice? current-list u0 pos) ERR-SLICE-FAILED))
                  (after-slice (unwrap! (slice? current-list (+ pos u1) (len current-list)) ERR-SLICE-FAILED))
                  (updated-list (unwrap! (as-max-len? (concat before-slice after-slice) u20) ERR-TOO-LONG)))
              (var-set seat-holders updated-list)
              (ok true))
        (ok false))))  ;; If position not found, do nothing

;; Main functions
;; Buy seats in Period 1
(define-public (buy-up-to (seat-count uint))
    (let (
        (current-seats (var-get total-seats-taken))
        (user-seats (default-to u0 (map-get? seats-owned tx-sender)))
        (max-total-allowed (get-max-seats-allowed))
        (max-additional-allowed (if (>= user-seats max-total-allowed)
                                  u0
                                  (- max-total-allowed user-seats)))
        (actual-seats (if (> seat-count max-additional-allowed) 
                        max-additional-allowed
                        seat-count)))
        
        (asserts! (> actual-seats u0) ERR-INVALID-SEAT-COUNT)
        (asserts! (< current-seats SEATS) ERR-NO-SEATS-LEFT)
        (asserts! (is-none (var-get period-2-height)) ERR-PERIOD-2-ALREADY-STARTED)
        
        ;; Process payment
        (match (stx-transfer? (* PRICE-PER-SEAT actual-seats) tx-sender (as-contract tx-sender))
            success 
                (begin
                    (if (is-eq user-seats u0) 
                        (var-set total-users (+ (var-get total-users) u1))
                        true)
                    (map-set seats-owned tx-sender (+ user-seats actual-seats))
                    (var-set total-seats-taken (+ current-seats actual-seats))
                    (var-set stx-balance (+ (var-get stx-balance) (* PRICE-PER-SEAT actual-seats)))
                    (update-seat-holder tx-sender (+ user-seats actual-seats))
                    
                    (if (and (>= (var-get total-users) MIN-USERS)  ;; Check if we should start Period 2
                            (>= (var-get total-seats-taken) SEATS))
                        (var-set period-2-height (some burn-block-height))
                        true)
                    (print {
                        type: "buy-seats",
                        buyer: tx-sender,
                        seats-owned: (+ user-seats actual-seats),
                        total-users: (var-get total-users),
                        total-seats-taken: (+ current-seats actual-seats),
                        stx-balance: (var-get stx-balance),
                        seat-holders: (var-get seat-holders),
                        period-2-height: (var-get period-2-height) ;; perhaps these var-get can be optimized?
                        })
                    (ok true))
            error (err error))))

;; Get highest seat holder for Period 2 reductions
(define-private (get-highest-seat-holder)
    (let ((holders (var-get seat-holders)))
      (if (> (len holders) u0)
          (let ((first-holder (unwrap-panic (element-at holders u0))))
            (some (get owner (fold check-highest holders first-holder))))
          none)))

(define-private (check-highest 
    (entry {owner: principal, seats: uint}) 
    (current-max {owner: principal, seats: uint}))
  (if (>= (get seats entry) (get seats current-max))
      entry
      current-max))

;; Buy exactly one seat in Period 2
(define-public (buy-single-seat)
    (let (
        (current-seats (var-get total-seats-taken))
        (highest-holder (get-highest-seat-holder))
        (holder (unwrap! highest-holder ERR-HIGHEST-HOLDER))
        (old-seats (default-to u0 (map-get? seats-owned holder))))
        
        (asserts! (is-some (var-get period-2-height)) ERR-PERIOD-2-NOT-INITIALIZED)
        (asserts! (is-in-period-2) ERR-ALREADY-EXPIRED)
        (asserts! (< (var-get total-users) SEATS) ERR-NO-SEATS-LEFT)
        (asserts! (> old-seats u1) ERR-HIGHEST-ONE-SEAT)
        
        ;; Process payment and refund highest holder
        (match (stx-transfer? PRICE-PER-SEAT tx-sender holder)
            success 
                (begin
                    ;; Update new buyer
                    (var-set total-users (+ (var-get total-users) u1))
                    (map-set seats-owned holder (- old-seats u1))
                    (map-set seats-owned tx-sender u1)
                    (update-seat-holder holder (- old-seats u1))  ;; Update list for holder
                    (update-seat-holder tx-sender u1)             ;; Update list for buyer
                    (print {
                        type: "buy-single-seat",
                        total-users: (var-get total-users),
                        holder: holder,
                        holder-seats: (- old-seats u1),
                        buyer: tx-sender,
                        buyer-seats: u1,
                        seat-holders: (var-get seat-holders),
                         })
                    (ok true))
            error (err error))))

;; Refund logic only for Period 1 expired and Period 2 not started
(define-public (refund)
    (let (
        (user-seats (default-to u0 (map-get? seats-owned tx-sender)))
        (seat-owner tx-sender))
        (asserts! (is-period-1-expired) ERR-NOT-EXPIRED) ;; period 1 is expired
        (asserts! (is-none (var-get period-2-height)) ERR-PERIOD-2-ALREADY-STARTED)
        (asserts! (> user-seats u0) ERR-NOT-SEAT-OWNER)
        
        ;; Process refund
        (match (as-contract (stx-transfer? (* PRICE-PER-SEAT user-seats) tx-sender seat-owner))
            success 
                (let ((is-removed (unwrap! (remove-seat-holder tx-sender) ERR-REMOVING-HOLDER)))
                    (map-delete seats-owned tx-sender)
                    (var-set total-seats-taken (- (var-get total-seats-taken) user-seats))
                    (var-set total-users (- (var-get total-users) u1))
                    (var-set stx-balance (- (var-get stx-balance) (* PRICE-PER-SEAT user-seats)))
                    (print {
                        type: "refund",
                        user: tx-sender,
                        seat-holders: (var-get seat-holders),
                        total-seats-taken: (var-get total-seats-taken),
                        total-users: (var-get total-users),
                        stx-balance: (var-get stx-balance)
                        })
                    (ok true))
            error (err error))))

;; Calculate claimable amount based on vesting schedule
(define-private (get-claimable-amount (owner principal))
    (match (var-get distribution-height) 
        start-height 
            (let ((claimed (default-to u0 (map-get? claimed-amounts owner)))
                  (seats-owner (default-to u0 (map-get? seats-owned owner)))
                  (vested (fold check-claimable VESTING-SCHEDULE u0)))
                (- (* vested seats-owner) claimed)) ;; double claiming is impossible    
        u0)) ;; If distribution not initialized, nothing is claimable

(define-private (check-claimable (entry {height: uint, percent: uint, id: uint}) (current-total uint))
    (if (<= (+ (unwrap-panic (var-get distribution-height)) (get height entry)) burn-block-height)
        (+ current-total (/ (* TOKENS-PER-SEAT (get percent entry)) u100))
        (if (and 
            (var-get accelerated-vesting)   ;; token graduated, accelerated vesting
            (<= (get id entry) u2))  ;; we're in first 3 entries (0,1,2)
            (+ current-total (/ (* TOKENS-PER-SEAT (get percent entry)) u100))
            current-total)))

;; Claim vested tokens
(define-public (claim (ft <faktory-token>))
    (let ((claimable (get-claimable-amount tx-sender))
          (seat-owner tx-sender))
        (asserts! (is-eq (var-get token-contract) (var-get dao-token)) ERR-DISTRIBUTION-NOT-INITIALIZED) 
        (asserts! (is-eq (contract-of ft) (unwrap-panic (var-get dao-token))) ERR-WRONG-TOKEN)
        (asserts! (> (default-to u0 (map-get? seats-owned tx-sender)) u0) ERR-NOT-SEAT-OWNER)
        (asserts! (> claimable u0) ERR-NOTHING-TO-CLAIM)
        (asserts! (>= (var-get ft-balance) claimable) ERR-CONTRACT-INSUFFICIENT-FUNDS)
        (match (as-contract (contract-call? ft transfer claimable tx-sender seat-owner none))
            success
                (begin
                    (map-set claimed-amounts tx-sender 
                        (+ (default-to u0 (map-get? claimed-amounts tx-sender)) claimable))
                    (var-set ft-balance (- (var-get ft-balance) claimable)) ;; reduce ft-balance by claimable
                    (print {
                        type: "claim",
                        user: tx-sender,
                        amount-claimed: claimable,
                        total-claimed: (map-get? claimed-amounts tx-sender),
                        ft-balance: (var-get ft-balance)
                        })
                    (ok claimable))
            error (err error))))

;; Read only functions
(define-read-only (get-max-seats-allowed)
    (let (
        (seats-remaining (- SEATS (var-get total-seats-taken)))    ;; 13 seats left
        (users-remaining (- MIN-USERS (var-get total-users)))      ;; 9 users needed
        (max-possible (+ (- seats-remaining users-remaining) u1))) ;; (13 - 9) + 1 = 5 seats possible
        (if (>= max-possible MAX-SEATS-PER-USER)
            MAX-SEATS-PER-USER
            max-possible)))

(define-read-only (get-contract-status)
    (ok 
    {
        is-period-1-expired: (is-period-1-expired),
        period-2-started: (is-some (var-get period-2-height)),
        is-in-period-2: (is-in-period-2),
        total-users: (var-get total-users),
        total-seats-taken: (var-get total-seats-taken),
        distribution-initialized: (is-some (var-get token-contract))
    }))

(define-read-only (get-user-info (user principal))
    (ok
    {
        seats-owned: (default-to u0 (map-get? seats-owned user)),
        amount-claimed: (default-to u0 (map-get? claimed-amounts user)),
        claimable-amount: (get-claimable-amount user)
    }))

(define-read-only (get-period-2-info)
    (ok
    {
        highest-holder: (get-highest-seat-holder),
        period-2-blocks-remaining: (match (var-get period-2-height)
            start (- (+ start PERIOD-2-LENGTH) burn-block-height)
            u0)
    }))

(define-read-only (get-remaining-seats)
    (ok {remainin-seats: (- SEATS (var-get total-seats-taken))}))

(define-read-only (get-seats-owned (address principal))
    (ok {seats-owned:
    (> (default-to u0 (map-get? seats-owned address)) u0)}))

(define-read-only (get-claimed-amount (address principal))
    (ok {claimed-amount:
    (default-to u0 (map-get? claimed-amounts address))}))

(define-read-only (get-vesting-schedule)
    (ok {vesting-schedule: VESTING-SCHEDULE}))

(define-read-only (get-seat-holders)
    (ok {seat-holders: (var-get seat-holders)}))

;; A multi-sig creator contract addresses after creating a multi-sig whose owners are 10 buyers resulting from period 1
(define-public (set-contract-addresses (new-multi-sig principal) (new-dao-token principal) (new-dex-contract principal))
    (begin
        (asserts! (is-some (var-get period-2-height)) ERR-PERIOD-2-NOT-INITIALIZED)
        (asserts! (is-eq contract-caller MULTI-SIG-CREATOR) ERR-NOT-AUTHORIZED)

        (var-set dao-multi-sig (some new-multi-sig))
        (var-set dao-token (some new-dao-token))
        (var-set dex-contract (some new-dex-contract))
        
        (print {
            type: "contract-addresses-updated",
            dao-multi-sig: new-multi-sig,
            dao-token: new-dao-token,
            dex-contract: new-dex-contract,
            multi-sig-creator: contract-caller
        })
        (ok true)))

;; on DAO token deployment
(define-public (initialize-token-distribution)
    (begin
        (asserts! (is-some (var-get period-2-height)) ERR-PERIOD-2-NOT-INITIALIZED)
        (asserts! (is-eq (some tx-sender) (var-get dao-token)) ERR-NOT-AUTHORIZED)
        (asserts! (is-none (var-get token-contract)) ERR-ALREADY-INITIALIZED)
        (asserts! (is-some (var-get dao-multi-sig)) ERR-NOT-SET)
        (asserts! (is-some (var-get dao-token)) ERR-NOT-SET)
        (asserts! (is-some (var-get dex-contract)) ERR-NOT-SET)
        (try! (as-contract (stx-transfer? u100000000 tx-sender (unwrap-panic (var-get dex-contract)))))  ;; 100 STX to DEX
        (try! (as-contract (stx-transfer? u10000000 tx-sender (unwrap-panic  (var-get dao-multi-sig)))))   ;; 10 STX to multi-sig/admin -> covers contract deployment fees
        (try! (as-contract (stx-transfer? u40000000 tx-sender MULTI-SIG-CREATOR))) ;; 40 STX fee to multi-sig creator -> covers Runes fees
        (var-set token-contract (some tx-sender))
        (var-set distribution-height (some burn-block-height))
        (var-set ft-balance FT-INITIALIZED-BALANCE) ;; 20M tokens
        (print {
            type: "distribution-initialized",
            token-contract: (var-get dao-token),
            distribution-height: burn-block-height,
            ft-balance: FT-INITIALIZED-BALANCE
        })
        (ok true)))

;; on Bonding
(define-public (toggle-accelerated-vesting)
    (begin
        (asserts! (is-eq contract-caller (unwrap-panic (var-get dex-contract))) ERR-NOT-AUTHORIZED)
        (ok (var-set accelerated-vesting true))))

;; boot contract
(var-set deployment-height (some burn-block-height))