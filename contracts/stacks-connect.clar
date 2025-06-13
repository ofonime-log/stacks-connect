;; StacksConnect: Bitcoin-Native Social Network
;; A decentralized social platform built for the Bitcoin ecosystem
;;
;; Summary:
;; StacksConnect leverages Stacks Layer 2 to create a censorship-resistant social network
;; where users maintain sovereign control over their data, relationships, and digital identity.
;; Built on Bitcoin's security foundation with smart contract functionality.
;;
;; Description:
;; This contract implements a comprehensive social networking protocol featuring:
;; - Sovereign user identity and profile management
;; - Decentralized friendship and blocking systems  
;; - Privacy-first architecture with granular controls
;; - Rate limiting and spam protection mechanisms
;; - Batch processing for scalability optimization
;; - Bitcoin-aligned values of self-custody and censorship resistance
;;
;; The platform empowers users to build meaningful connections while maintaining
;; full ownership of their social graph and personal data, secured by Bitcoin's
;; immutable ledger through Stacks smart contracts.

;; ERROR CONSTANTS - Standardized Error Handling System

(define-constant ERR_NOT_FOUND (err u100))
(define-constant ERR_ALREADY_EXISTS (err u101))
(define-constant ERR_UNAUTHORIZED (err u102))
(define-constant ERR_INVALID_INPUT (err u103))
(define-constant ERR_BLOCKED (err u104))
(define-constant ERR_DEACTIVATED (err u105))
(define-constant ERR_RATE_LIMITED (err u106))
(define-constant ERR_BATCH_FULL (err u107))
(define-constant ERR_BATCH_EXPIRED (err u108))

;; STATUS CONSTANTS - Platform State Management

;; User Account Status Definitions
(define-constant STATUS_DEACTIVATED u0)
(define-constant STATUS_ACTIVE u1)
(define-constant STATUS_SUSPENDED u2)

;; Relationship Status Definitions
(define-constant FRIENDSHIP_PENDING u0)
(define-constant FRIENDSHIP_ACTIVE u1)
(define-constant FRIENDSHIP_BLOCKED u2)

;; PLATFORM LIMITS - Spam Protection & Resource Management

;; Daily Action Limits for Platform Stability
(define-constant MAX_ACTIONS_PER_DAY u100)
(define-constant MAX_FRIEND_REQUESTS_PER_DAY u20)
(define-constant MAX_STATUS_UPDATES_PER_DAY u24)
(define-constant RATE_LIMIT_RESET_PERIOD u86400) ;; 24 hours in seconds

;; Batch Processing Configuration
(define-constant MIN_BATCH_SIZE u10)
(define-constant MAX_BATCH_SIZE u100)
(define-constant BATCH_EXPIRY_PERIOD u3600) ;; 1 hour in seconds

;; DATA STORAGE MAPS - Core Platform State

;; Primary User Registry - Core Identity Management
(define-map Users
  principal
  {
    name: (string-ascii 64),
    status: uint,
    timestamp: uint,
    metadata: (optional (string-utf8 256)),
    deactivation-time: (optional uint),
    encryption-key: (optional (buff 32)),
    profile-image: (optional (string-utf8 256)),
  }
)

;; Privacy Control Center - Granular Visibility Settings
(define-map UserPrivacy
  principal
  {
    friend-list-visible: bool,
    status-visible: bool,
    metadata-visible: bool,
    last-seen-visible: bool,
    profile-image-visible: bool,
    encryption-enabled: bool,
    last-updated: uint,
  }
)

;; Rate Limiting Engine - Anti-Spam Protection
(define-map RateLimits
  principal
  {
    daily-actions: uint,
    friend-requests: uint,
    status-updates: uint,
    last-reset: uint,
  }
)

;; Batch Processing Optimizer - Performance Enhancement
(define-map UserBatches
  principal
  {
    message-counter: uint,
    last-batch-timestamp: uint,
    batch-size: uint,
    current-batch-items: uint,
    total-batches: uint,
  }
)

;; Activity Analytics - User Engagement Tracking
(define-map UserActivity
  principal
  {
    last-seen: uint,
    login-count: uint,
    total-actions: uint,
    last-action: uint,
  }
)

;; Social Graph Management - Friendship Relations
(define-map Friendships
  {
    user1: principal,
    user2: principal,
  }
  { status: uint }
)

;; Safety Infrastructure - User Blocking System
(define-map BlockedUsers
  {
    blocker: principal,
    blocked: principal,
  }
  { timestamp: uint }
)

;; PRIVATE UTILITY FUNCTIONS - Internal Logic Components

;; Rate Limit Validator - Automatic Reset & Validation
(define-private (check-rate-limit
    (user principal)
    (action-type uint)
  )
  (let (
      (rate-data (default-to {
        daily-actions: u0,
        friend-requests: u0,
        status-updates: u0,
        last-reset: stacks-block-height,
      }
        (map-get? RateLimits user)
      ))
      (current-time stacks-block-height)
      (should-reset (> (- current-time (get last-reset rate-data)) RATE_LIMIT_RESET_PERIOD))
    )
    (if should-reset
      (begin
        (map-set RateLimits user {
          daily-actions: u1,
          friend-requests: (if (is-eq action-type u1)
            u1
            u0
          ),
          status-updates: (if (is-eq action-type u2)
            u1
            u0
          ),
          last-reset: current-time,
        })
        true
      )
      (and
        (< (get daily-actions rate-data) MAX_ACTIONS_PER_DAY)
        (or
          (not (is-eq action-type u1))
          (< (get friend-requests rate-data) MAX_FRIEND_REQUESTS_PER_DAY)
        )
        (or
          (not (is-eq action-type u2))
          (< (get status-updates rate-data) MAX_STATUS_UPDATES_PER_DAY)
        )
      )
    )
  )
)

;; Rate Limit Counter - Action Tracking & Increment
(define-private (update-rate-limit
    (user principal)
    (action-type uint)
  )
  (let ((rate-data (unwrap-panic (map-get? RateLimits user))))
    (map-set RateLimits user
      (merge rate-data {
        daily-actions: (+ (get daily-actions rate-data) u1),
        friend-requests: (+ (get friend-requests rate-data)
          (if (is-eq action-type u1)
            u1
            u0
          )),
        status-updates: (+ (get status-updates rate-data)
          (if (is-eq action-type u2)
            u1
            u0
          )),
      })
    )
  )
)

;; Activity Logger - Comprehensive User Action Tracking
(define-private (update-user-activity (user principal))
  (let (
      (current-time stacks-block-height)
      (activity (default-to {
        last-seen: current-time,
        login-count: u0,
        total-actions: u0,
        last-action: current-time,
      }
        (map-get? UserActivity user)
      ))
    )
    (map-set UserActivity user
      (merge activity {
        last-seen: current-time,
        total-actions: (+ (get total-actions activity) u1),
        last-action: current-time,
      })
    )
  )
)

;; Mathematical Utilities - Optimization Helpers
(define-private (max-uint
    (a uint)
    (b uint)
  )
  (if (>= a b)
    a
    b
  )
)

(define-private (min-uint
    (a uint)
    (b uint)
  )
  (if (<= a b)
    a
    b
  )
)

;; Social Graph Validators - Relationship Verification
(define-private (are-friends
    (user1 principal)
    (user2 principal)
  )
  (match (map-get? Friendships {
    user1: user1,
    user2: user2,
  })
    friendship (is-eq (get status friendship) FRIENDSHIP_ACTIVE)
    false
  )
)

;; User Status Validators - Security & Access Control
(define-private (check-active-user (user principal))
  (match (map-get? Users user)
    user-data (and
      (is-eq (get status user-data) STATUS_ACTIVE)
      (is-none (get deactivation-time user-data))
    )
    false
  )
)

(define-private (user-exists (user principal))
  (is-some (map-get? Users user))
)

;; Safety Validators - Blocking & Protection
(define-private (is-blocked
    (blocker principal)
    (blocked principal)
  )
  (is-some (map-get? BlockedUsers {
    blocker: blocker,
    blocked: blocked,
  }))
)

;; Privacy Settings Accessor - Secure Default Configuration
(define-private (get-privacy-settings (user principal))
  (default-to {
    friend-list-visible: true,
    status-visible: true,
    metadata-visible: true,
    last-seen-visible: true,
    profile-image-visible: true,
    encryption-enabled: false,
    last-updated: stacks-block-height,
  }
    (map-get? UserPrivacy user)
  )
)

;; PUBLIC INTERFACE FUNCTIONS - External API Endpoints

;; Intelligent Batch Optimization - Dynamic Performance Tuning
(define-public (optimize-batch-size (user principal))
  (let (
      (batch-data (unwrap-panic (map-get? UserBatches user)))
      (current-time stacks-block-height)
      (time-since-last-batch (- current-time (get last-batch-timestamp batch-data)))
      (current-batch-size (get batch-size batch-data))
      (items-in-current-batch (get current-batch-items batch-data))
    )
    (if (> time-since-last-batch BATCH_EXPIRY_PERIOD)
      (begin
        (map-set UserBatches user
          (merge batch-data {
            batch-size: (max-uint MIN_BATCH_SIZE (/ current-batch-size u2)),
            current-batch-items: u0,
            last-batch-timestamp: current-time,
          })
        )
        (ok true)
      )
      (begin
        (map-set UserBatches user
          (merge batch-data { batch-size: (min-uint MAX_BATCH_SIZE
            (if (>= items-in-current-batch (/ current-batch-size u2))
              (* current-batch-size u2)
              current-batch-size
            )) }
          ))
        (ok true)
      )
    )
  )
)

;; Advanced Privacy Configuration - Granular Control Center
(define-public (update-advanced-privacy-settings
    (friend-list-visible bool)
    (status-visible bool)
    (metadata-visible bool)
    (last-seen-visible bool)
    (profile-image-visible bool)
    (encryption-enabled bool)
  )
  (let ((caller tx-sender))
    (asserts! (check-active-user caller) ERR_DEACTIVATED)
    (asserts! (check-rate-limit caller u2) ERR_RATE_LIMITED)
    (map-set UserPrivacy caller {
      friend-list-visible: friend-list-visible,
      status-visible: status-visible,
      metadata-visible: metadata-visible,
      last-seen-visible: last-seen-visible,
      profile-image-visible: profile-image-visible,
      encryption-enabled: encryption-enabled,
      last-updated: stacks-block-height,
    })
    (update-rate-limit caller u2)
    (update-user-activity caller)
    (print {
      event: "privacy-updated",
      user: caller,
      timestamp: stacks-block-height,
    })
    (ok true)
  )
)

;; Flexible Profile Management - Dynamic User Data Updates
(define-public (update-user-profile
    (name (optional (string-ascii 64)))
    (metadata (optional (string-utf8 256)))
    (encryption-key (optional (buff 32)))
    (profile-image (optional (string-utf8 256)))
  )
  (let (
      (caller tx-sender)
      (user (unwrap-panic (map-get? Users caller)))
    )
    (asserts! (check-active-user caller) ERR_DEACTIVATED)
    (asserts! (check-rate-limit caller u2) ERR_RATE_LIMITED)
    (map-set Users caller
      (merge user {
        name: (default-to (get name user) name),
        metadata: (if (is-some metadata)
          metadata
          (get metadata user)
        ),
        encryption-key: (if (is-some encryption-key)
          encryption-key
          (get encryption-key user)
        ),
        profile-image: (if (is-some profile-image)
          profile-image
          (get profile-image user)
        ),
      })
    )
    (update-rate-limit caller u2)
    (update-user-activity caller)
    (print {
      event: "profile-updated",
      user: caller,
      timestamp: stacks-block-height,
    })
    (ok true)
  )
)

;; Manual Batch Configuration - Advanced User Control
(define-public (set-batch-size (new-size uint))
  (let (
      (caller tx-sender)
      (batch-data (unwrap-panic (map-get? UserBatches caller)))
    )
    (asserts! (check-active-user caller) ERR_DEACTIVATED)
    (asserts! (and (>= new-size MIN_BATCH_SIZE) (<= new-size MAX_BATCH_SIZE))
      ERR_INVALID_INPUT
    )
    (map-set UserBatches caller (merge batch-data { batch-size: new-size }))
    (print {
      event: "batch-size-updated",
      user: caller,
      new-size: new-size,
      timestamp: stacks-block-height,
    })
    (ok true)
  )
)

;; Session Management - Security & Analytics Tracking
(define-public (record-login)
  (let (
      (caller tx-sender)
      (activity (default-to {
        last-seen: stacks-block-height,
        login-count: u0,
        total-actions: u0,
        last-action: stacks-block-height,
      }
        (map-get? UserActivity caller)
      ))
    )
    (map-set UserActivity caller
      (merge activity {
        last-seen: stacks-block-height,
        login-count: (+ (get login-count activity) u1),
      })
    )
    (print {
      event: "user-login",
      user: caller,
      timestamp: stacks-block-height,
    })
    (ok true)
  )
)
