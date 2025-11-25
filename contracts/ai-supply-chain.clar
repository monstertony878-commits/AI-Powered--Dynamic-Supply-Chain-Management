(impl-trait .sip-010-ft-trait.sip-010-trait)

(define-constant ERR-NOT-ADMIN (err u100))
(define-constant ERR-UNAUTHORIZED-ORACLE (err u101))
(define-constant ERR-UNKNOWN-SHIPMENT (err u102))
(define-constant ERR-INVALID-STATUS (err u103))
(define-constant ERR-SHIPMENT-NOT-OPEN (err u104))
(define-constant ERR-INSUFFICIENT-ESCROW (err u105))
(define-constant ERR-ALREADY-FINALIZED (err u106))

(define-data-var admin principal tx-sender)

;; IoT / AI oracles allowed to push status updates
(define-data-var allowed-oracle (list 5 principal) (list))

;; Shipment status enum
(define-constant STATUS-OPEN u0)          ;; created, in transit
(define-constant STATUS-ONTIME u1)       ;; arrived on time + healthy
(define-constant STATUS-DELAYED u2)      ;; delay detected by AI
(define-constant STATUS-QUALITY-ISSUE u3) ;; quality/temp issue
(define-constant STATUS-ESCALATED u4)    ;; escalated for manual review
(define-constant STATUS-FINAL u5)        ;; closed, payment handled

(define-map shipments
  ((id uint))
  ((buyer principal)
   (supplier principal)
   (carrier principal)
   (oracle principal)
   (escrow-amount uint)
   (released-amount uint)
   (penalty-amount uint)
   (status uint)))

;; --- Admin functions ---

(define-public (set-admin (new-admin principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-ADMIN)
    (var-set admin new-admin)
    (ok new-admin)))

(define-public (add-oracle (oracle principal))
  (begin
    (asserts! (is-eq tx-sender (var-get admin)) ERR-NOT-ADMIN)
    (let ((current (var-get allowed-oracle)))
      (var-set allowed-oracle (append current (list oracle)))
      (ok true))))

;; --- Core flows ---

;; Buyer locks STX in escrow for a shipment
(define-public (create-shipment
    (id uint)
    (supplier principal)
    (carrier principal)
    (oracle principal)
    (escrow-amount uint))
  (begin
    (asserts! (>= escrow-amount u1) (err u200))
    (let ((existing (map-get? shipments ((id id)))))
      (match existing
        some _ (err u201) ;; shipment already exists
        none
          (begin
            (asserts! (is-ok (stx-transfer? escrow-amount tx-sender (as-contract tx-sender))) ERR-INSUFFICIENT-ESCROW)
            (map-set shipments
              ((id id))
              ((buyer tx-sender)
               (supplier supplier)
               (carrier carrier)
               (oracle oracle)
               (escrow-amount escrow-amount)
               (released-amount u0)
               (penalty-amount u0)
               (status STATUS-OPEN)))
            (ok id)))))

;; IoT / AI oracle updates status based on off-chain analytics
(define-public (update-status
    (id uint)
    (new-status uint)
    (penalty uint))
  (let ((shipment (map-get? shipments ((id id))))
        (oracle-list (var-get allowed-oracle)))
    (match shipment shipment-data
      (begin
        (asserts! (is-eq (get oracle shipment-data) tx-sender) ERR-UNAUTHORIZED-ORACLE)
        (asserts! (or (is-eq new-status STATUS-ONTIME)
                      (is-eq new-status STATUS-DELAYED)
                      (is-eq new-status STATUS-QUALITY-ISSUE)
                      (is-eq new-status STATUS-ESCALATED)) ERR-INVALID-STATUS)
        (asserts! (not (is-eq (get status shipment-data) STATUS-FINAL)) ERR-ALREADY-FINALIZED)
        (map-set shipments
          ((id id))
          ((buyer (get buyer shipment-data))
           (supplier (get supplier shipment-data))
           (carrier (get carrier shipment-data))
           (oracle (get oracle shipment-data))
           (escrow-amount (get escrow-amount shipment-data))
           (released-amount (get released-amount shipment-data))
           (penalty-amount penalty)
           (status new-status)))
        (ok true))
      (err ERR-UNKNOWN-SHIPMENT))))

;; Anyone can finalize once status is terminal; funds flow based on status
(define-public (finalize-shipment (id uint))
  (let ((shipment (map-get? shipments ((id id)))))
    (match shipment shipment-data
      (let ((status (get status shipment-data))
            (escrow (get escrow-amount shipment-data))
            (penalty (get penalty-amount shipment-data)))
        (asserts! (not (is-eq status STATUS-FINAL)) ERR-ALREADY-FINALIZED)
        (asserts! (not (is-eq status STATUS-OPEN)) ERR-SHIPMENT-NOT-OPEN)
        (let ((supplier (get supplier shipment-data))
              (buyer (get buyer shipment-data))
              (payout (if (or (is-eq status STATUS-ONTIME)
                              (is-eq status STATUS-ESCALATED))
                          escrow
                          (if (<= penalty escrow) (- escrow penalty) u0)))
              (refund (if (> penalty escrow) u0 penalty)))
          (begin
            (if (> payout u0)
              (asserts! (is-ok (stx-transfer? payout (as-contract tx-sender) supplier)) ERR-INSUFFICIENT-ESCROW)
              (ok u0))
            (if (> refund u0)
              (asserts! (is-ok (stx-transfer? refund (as-contract tx-sender) buyer)) ERR-INSUFFICIENT-ESCROW)
              (ok u0))
            (map-set shipments
              ((id id))
              ((buyer buyer)
               (supplier supplier)
               (carrier (get carrier shipment-data))
               (oracle (get oracle shipment-data))
               (escrow-amount escrow)
               (released-amount payout)
               (penalty-amount penalty)
               (status STATUS-FINAL)))
            (ok (tuple (payout payout) (refund refund))))))
      (err ERR-UNKNOWN-SHIPMENT))))

;; --- Read-only helpers ---

(define-read-only (get-shipment (id uint))
  (map-get? shipments ((id id))))

(define-read-only (get-admin)
  (ok (var-get admin)))

(define-read-only (get-oracles)
  (var-get allowed-oracle))
