// Gerado por `pnpm db:types` (scripts/db/gen-types.mjs, schema public). Não editar à mão.

export type Json = string | number | boolean | null | { [key: string]: Json | undefined } | Json[];

export type Database = {
  public: {
    Tables: {
      action_plans: {
        Row: {
          created_at: string;
          created_by: string | null;
          due_on: string | null;
          id: string;
          owner_id: string | null;
          status: Database["public"]["Enums"]["action_plan_status"];
          store_id: string;
          template_item_id: string;
          trigger_count: number;
          updated_at: string;
          what: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by?: string | null;
          due_on?: string | null;
          id?: string;
          owner_id?: string | null;
          status?: Database["public"]["Enums"]["action_plan_status"];
          store_id: string;
          template_item_id: string;
          trigger_count?: number;
          updated_at?: string;
          what: string;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          due_on?: string | null;
          id?: string;
          owner_id?: string | null;
          status?: Database["public"]["Enums"]["action_plan_status"];
          store_id?: string;
          template_item_id?: string;
          trigger_count?: number;
          updated_at?: string;
          what?: string;
        };
        Relationships: [
          {
            foreignKeyName: "action_plans_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "action_plans_owner_id_fkey";
            columns: ["owner_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "action_plans_store_id_fkey";
            columns: ["store_id"];
            isOneToOne: false;
            referencedRelation: "stores";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "action_plans_template_item_id_fkey";
            columns: ["template_item_id"];
            isOneToOne: false;
            referencedRelation: "template_items";
            referencedColumns: ["id"];
          },
        ];
      };
      attempt_item_answers: {
        Row: {
          answered_at: string;
          attempt_id: string;
          checked: boolean;
          id: string;
          note: string | null;
          task_id: string;
          task_item_id: string;
        };
        ComputedFields: never;
        Insert: {
          answered_at?: string;
          attempt_id: string;
          checked?: boolean;
          id?: string;
          note?: string | null;
          task_id: string;
          task_item_id: string;
        };
        Update: {
          answered_at?: string;
          attempt_id?: string;
          checked?: boolean;
          id?: string;
          note?: string | null;
          task_id?: string;
          task_item_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "attempt_item_answers_attempt_id_fkey";
            columns: ["attempt_id"];
            isOneToOne: false;
            referencedRelation: "task_attempts";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "attempt_item_answers_attempt_task_fkey";
            columns: ["attempt_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "task_attempts";
            referencedColumns: ["id", "task_id"];
          },
          {
            foreignKeyName: "attempt_item_answers_item_task_fkey";
            columns: ["task_item_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "task_items";
            referencedColumns: ["id", "task_id"];
          },
          {
            foreignKeyName: "attempt_item_answers_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "attempt_item_answers_task_item_id_fkey";
            columns: ["task_item_id"];
            isOneToOne: false;
            referencedRelation: "task_items";
            referencedColumns: ["id"];
          },
        ];
      };
      audit_log: {
        Row: {
          action: string;
          actor_id: string | null;
          diff: NonNullable<Json>;
          id: number;
          occurred_at: string;
          organization_id: string | null;
          record_id: string | null;
          table_name: string | null;
        };
        ComputedFields: never;
        Insert: {
          action: string;
          actor_id?: string | null;
          diff?: NonNullable<Json>;
          id?: never;
          occurred_at?: string;
          organization_id?: string | null;
          record_id?: string | null;
          table_name?: string | null;
        };
        Update: {
          action?: string;
          actor_id?: string | null;
          diff?: NonNullable<Json>;
          id?: never;
          occurred_at?: string;
          organization_id?: string | null;
          record_id?: string | null;
          table_name?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "audit_log_actor_id_fkey";
            columns: ["actor_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      data_requests: {
        Row: {
          created_at: string;
          details: string;
          id: string;
          kind: Database["public"]["Enums"]["data_request_kind"];
          organization_id: string;
          profile_id: string;
          resolution: string | null;
          resolved_at: string | null;
          resolved_by: string | null;
          status: string;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          details: string;
          id?: string;
          kind: Database["public"]["Enums"]["data_request_kind"];
          organization_id: string;
          profile_id: string;
          resolution?: string | null;
          resolved_at?: string | null;
          resolved_by?: string | null;
          status?: string;
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          details?: string;
          id?: string;
          kind?: Database["public"]["Enums"]["data_request_kind"];
          organization_id?: string;
          profile_id?: string;
          resolution?: string | null;
          resolved_at?: string | null;
          resolved_by?: string | null;
          status?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "data_requests_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "data_requests_profile_id_fkey";
            columns: ["profile_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "data_requests_resolved_by_fkey";
            columns: ["resolved_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
        ];
      };
      evidences: {
        Row: {
          accuracy_m: number | null;
          attempt_id: string;
          captured_at_device: string | null;
          client_mutation_id: string | null;
          id: string;
          latitude: number | null;
          longitude: number | null;
          organization_id: string;
          phash: number | null;
          purged_at: string | null;
          received_at_server: string;
          sha256: string;
          similar_to_id: string | null;
          size_bytes: number | null;
          storage_path: string;
          store_id: string;
          suspicion: string[];
          task_id: string;
          task_item_id: string | null;
        };
        ComputedFields: never;
        Insert: {
          accuracy_m?: number | null;
          attempt_id: string;
          captured_at_device?: string | null;
          client_mutation_id?: string | null;
          id?: string;
          latitude?: number | null;
          longitude?: number | null;
          organization_id: string;
          phash?: number | null;
          purged_at?: string | null;
          received_at_server?: string;
          sha256: string;
          similar_to_id?: string | null;
          size_bytes?: number | null;
          storage_path: string;
          store_id: string;
          suspicion?: string[];
          task_id: string;
          task_item_id?: string | null;
        };
        Update: {
          accuracy_m?: number | null;
          attempt_id?: string;
          captured_at_device?: string | null;
          client_mutation_id?: string | null;
          id?: string;
          latitude?: number | null;
          longitude?: number | null;
          organization_id?: string;
          phash?: number | null;
          purged_at?: string | null;
          received_at_server?: string;
          sha256?: string;
          similar_to_id?: string | null;
          size_bytes?: number | null;
          storage_path?: string;
          store_id?: string;
          suspicion?: string[];
          task_id?: string;
          task_item_id?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "evidences_attempt_id_fkey";
            columns: ["attempt_id"];
            isOneToOne: false;
            referencedRelation: "task_attempts";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "evidences_attempt_task_fkey";
            columns: ["attempt_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "task_attempts";
            referencedColumns: ["id", "task_id"];
          },
          {
            foreignKeyName: "evidences_item_task_fkey";
            columns: ["task_item_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "task_items";
            referencedColumns: ["id", "task_id"];
          },
          {
            foreignKeyName: "evidences_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "evidences_similar_to_id_fkey";
            columns: ["similar_to_id"];
            isOneToOne: false;
            referencedRelation: "evidences";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "evidences_store_id_fkey";
            columns: ["store_id"];
            isOneToOne: false;
            referencedRelation: "stores";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "evidences_store_organization_fkey";
            columns: ["store_id", "organization_id"];
            isOneToOne: false;
            referencedRelation: "stores";
            referencedColumns: ["id", "organization_id"];
          },
          {
            foreignKeyName: "evidences_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "evidences_task_item_id_fkey";
            columns: ["task_item_id"];
            isOneToOne: false;
            referencedRelation: "task_items";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "evidences_task_store_fkey";
            columns: ["task_id", "store_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["id", "store_id"];
          },
        ];
      };
      memberships: {
        Row: {
          created_at: string;
          ends_at: string | null;
          id: string;
          organization_id: string;
          profile_id: string;
          role: Database["public"]["Enums"]["membership_role"];
          sector_id: string | null;
          starts_at: string;
          store_id: string | null;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          ends_at?: string | null;
          id?: string;
          organization_id: string;
          profile_id: string;
          role: Database["public"]["Enums"]["membership_role"];
          sector_id?: string | null;
          starts_at?: string;
          store_id?: string | null;
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          ends_at?: string | null;
          id?: string;
          organization_id?: string;
          profile_id?: string;
          role?: Database["public"]["Enums"]["membership_role"];
          sector_id?: string | null;
          starts_at?: string;
          store_id?: string | null;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "memberships_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "memberships_profile_id_fkey";
            columns: ["profile_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "memberships_sector_id_fkey";
            columns: ["sector_id"];
            isOneToOne: false;
            referencedRelation: "sectors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "memberships_sector_store_fkey";
            columns: ["sector_id", "store_id"];
            isOneToOne: false;
            referencedRelation: "sectors";
            referencedColumns: ["id", "store_id"];
          },
          {
            foreignKeyName: "memberships_store_id_fkey";
            columns: ["store_id"];
            isOneToOne: false;
            referencedRelation: "stores";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "memberships_store_organization_fkey";
            columns: ["store_id", "organization_id"];
            isOneToOne: false;
            referencedRelation: "stores";
            referencedColumns: ["id", "organization_id"];
          },
        ];
      };
      notifications: {
        Row: {
          channel: Database["public"]["Enums"]["notification_channel"];
          created_at: string;
          dedupe_key: string;
          id: string;
          payload: NonNullable<Json>;
          read_at: string | null;
          recipient_id: string;
          sent_at: string | null;
          store_id: string | null;
          task_id: string | null;
          type: Database["public"]["Enums"]["notification_type"];
        };
        ComputedFields: never;
        Insert: {
          channel?: Database["public"]["Enums"]["notification_channel"];
          created_at?: string;
          dedupe_key: string;
          id?: string;
          payload?: NonNullable<Json>;
          read_at?: string | null;
          recipient_id: string;
          sent_at?: string | null;
          store_id?: string | null;
          task_id?: string | null;
          type: Database["public"]["Enums"]["notification_type"];
        };
        Update: {
          channel?: Database["public"]["Enums"]["notification_channel"];
          created_at?: string;
          dedupe_key?: string;
          id?: string;
          payload?: NonNullable<Json>;
          read_at?: string | null;
          recipient_id?: string;
          sent_at?: string | null;
          store_id?: string | null;
          task_id?: string | null;
          type?: Database["public"]["Enums"]["notification_type"];
        };
        Relationships: [
          {
            foreignKeyName: "notifications_recipient_id_fkey";
            columns: ["recipient_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "notifications_store_id_fkey";
            columns: ["store_id"];
            isOneToOne: false;
            referencedRelation: "stores";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "notifications_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
        ];
      };
      organizations: {
        Row: {
          created_at: string;
          id: string;
          name: string;
          photo_retention_days: number;
          slug: string;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          id?: string;
          name: string;
          photo_retention_days?: number;
          slug: string;
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          name?: string;
          photo_retention_days?: number;
          slug?: string;
          updated_at?: string;
        };
        Relationships: [];
      };
      profiles: {
        Row: {
          created_at: string;
          full_name: string;
          id: string;
          status: Database["public"]["Enums"]["profile_status"];
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          full_name?: string;
          id: string;
          status?: Database["public"]["Enums"]["profile_status"];
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          full_name?: string;
          id?: string;
          status?: Database["public"]["Enums"]["profile_status"];
          updated_at?: string;
        };
        Relationships: [];
      };
      review_item_flags: {
        Row: {
          created_at: string;
          review_id: string;
          task_id: string;
          task_item_id: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          review_id: string;
          task_id: string;
          task_item_id: string;
        };
        Update: {
          created_at?: string;
          review_id?: string;
          task_id?: string;
          task_item_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "review_item_flags_item_task_fkey";
            columns: ["task_item_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "task_items";
            referencedColumns: ["id", "task_id"];
          },
          {
            foreignKeyName: "review_item_flags_review_id_fkey";
            columns: ["review_id"];
            isOneToOne: false;
            referencedRelation: "reviews";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "review_item_flags_review_task_fkey";
            columns: ["review_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "reviews";
            referencedColumns: ["id", "task_id"];
          },
          {
            foreignKeyName: "review_item_flags_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "review_item_flags_task_item_id_fkey";
            columns: ["task_item_id"];
            isOneToOne: false;
            referencedRelation: "task_items";
            referencedColumns: ["id"];
          },
        ];
      };
      reviews: {
        Row: {
          attempt_id: string;
          decision: Database["public"]["Enums"]["review_decision"];
          id: string;
          is_auto: boolean;
          reason: string | null;
          reviewed_at: string;
          reviewer_id: string | null;
          task_id: string;
        };
        ComputedFields: never;
        Insert: {
          attempt_id: string;
          decision: Database["public"]["Enums"]["review_decision"];
          id?: string;
          is_auto?: boolean;
          reason?: string | null;
          reviewed_at?: string;
          reviewer_id?: string | null;
          task_id: string;
        };
        Update: {
          attempt_id?: string;
          decision?: Database["public"]["Enums"]["review_decision"];
          id?: string;
          is_auto?: boolean;
          reason?: string | null;
          reviewed_at?: string;
          reviewer_id?: string | null;
          task_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "reviews_attempt_id_fkey";
            columns: ["attempt_id"];
            isOneToOne: true;
            referencedRelation: "task_attempts";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "reviews_attempt_task_fkey";
            columns: ["attempt_id", "task_id"];
            isOneToOne: false;
            referencedRelation: "task_attempts";
            referencedColumns: ["id", "task_id"];
          },
          {
            foreignKeyName: "reviews_reviewer_id_fkey";
            columns: ["reviewer_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "reviews_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
        ];
      };
      schedules: {
        Row: {
          assignee_id: string | null;
          created_at: string;
          created_by: string | null;
          ends_on: string | null;
          frequency: Database["public"]["Enums"]["schedule_frequency"];
          id: string;
          is_active: boolean;
          rule: NonNullable<Json>;
          sector_id: string;
          starts_on: string;
          store_id: string;
          template_id: string;
          updated_at: string;
          window_end: string;
          window_start: string;
        };
        ComputedFields: never;
        Insert: {
          assignee_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          ends_on?: string | null;
          frequency?: Database["public"]["Enums"]["schedule_frequency"];
          id?: string;
          is_active?: boolean;
          rule?: NonNullable<Json>;
          sector_id: string;
          starts_on?: string;
          store_id: string;
          template_id: string;
          updated_at?: string;
          window_end: string;
          window_start: string;
        };
        Update: {
          assignee_id?: string | null;
          created_at?: string;
          created_by?: string | null;
          ends_on?: string | null;
          frequency?: Database["public"]["Enums"]["schedule_frequency"];
          id?: string;
          is_active?: boolean;
          rule?: NonNullable<Json>;
          sector_id?: string;
          starts_on?: string;
          store_id?: string;
          template_id?: string;
          updated_at?: string;
          window_end?: string;
          window_start?: string;
        };
        Relationships: [
          {
            foreignKeyName: "schedules_assignee_id_fkey";
            columns: ["assignee_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "schedules_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "schedules_sector_id_fkey";
            columns: ["sector_id"];
            isOneToOne: false;
            referencedRelation: "sectors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "schedules_sector_store_fkey";
            columns: ["sector_id", "store_id"];
            isOneToOne: false;
            referencedRelation: "sectors";
            referencedColumns: ["id", "store_id"];
          },
          {
            foreignKeyName: "schedules_store_id_fkey";
            columns: ["store_id"];
            isOneToOne: false;
            referencedRelation: "stores";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "schedules_template_id_fkey";
            columns: ["template_id"];
            isOneToOne: false;
            referencedRelation: "task_templates";
            referencedColumns: ["id"];
          },
        ];
      };
      sectors: {
        Row: {
          created_at: string;
          id: string;
          is_active: boolean;
          name: string;
          responsible_id: string | null;
          sort_order: number;
          store_id: string;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          id?: string;
          is_active?: boolean;
          name: string;
          responsible_id?: string | null;
          sort_order?: number;
          store_id: string;
          updated_at?: string;
        };
        Update: {
          created_at?: string;
          id?: string;
          is_active?: boolean;
          name?: string;
          responsible_id?: string | null;
          sort_order?: number;
          store_id?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "sectors_responsible_id_fkey";
            columns: ["responsible_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "sectors_store_id_fkey";
            columns: ["store_id"];
            isOneToOne: false;
            referencedRelation: "stores";
            referencedColumns: ["id"];
          },
        ];
      };
      store_settings: {
        Row: {
          awaiting_approval_hours: number;
          channels: NonNullable<Json>;
          created_at: string;
          daily_summary_at: string;
          due_soon_minutes: number;
          escalate_owner_hours: number;
          store_id: string;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          awaiting_approval_hours?: number;
          channels?: NonNullable<Json>;
          created_at?: string;
          daily_summary_at?: string;
          due_soon_minutes?: number;
          escalate_owner_hours?: number;
          store_id: string;
          updated_at?: string;
        };
        Update: {
          awaiting_approval_hours?: number;
          channels?: NonNullable<Json>;
          created_at?: string;
          daily_summary_at?: string;
          due_soon_minutes?: number;
          escalate_owner_hours?: number;
          store_id?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "store_settings_store_id_fkey";
            columns: ["store_id"];
            isOneToOne: true;
            referencedRelation: "stores";
            referencedColumns: ["id"];
          },
        ];
      };
      stores: {
        Row: {
          address: string | null;
          created_at: string;
          id: string;
          is_active: boolean;
          name: string;
          organization_id: string;
          timezone: string;
          updated_at: string;
        };
        ComputedFields: never;
        Insert: {
          address?: string | null;
          created_at?: string;
          id?: string;
          is_active?: boolean;
          name: string;
          organization_id: string;
          timezone?: string;
          updated_at?: string;
        };
        Update: {
          address?: string | null;
          created_at?: string;
          id?: string;
          is_active?: boolean;
          name?: string;
          organization_id?: string;
          timezone?: string;
          updated_at?: string;
        };
        Relationships: [
          {
            foreignKeyName: "stores_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
        ];
      };
      task_attempts: {
        Row: {
          attempt_number: number;
          client_mutation_id: string | null;
          id: string;
          note: string | null;
          performed_by: string;
          started_at: string;
          store_id: string;
          submit_client_mutation_id: string | null;
          submitted_at: string | null;
          task_id: string;
        };
        ComputedFields: never;
        Insert: {
          attempt_number: number;
          client_mutation_id?: string | null;
          id?: string;
          note?: string | null;
          performed_by: string;
          started_at?: string;
          store_id: string;
          submit_client_mutation_id?: string | null;
          submitted_at?: string | null;
          task_id: string;
        };
        Update: {
          attempt_number?: number;
          client_mutation_id?: string | null;
          id?: string;
          note?: string | null;
          performed_by?: string;
          started_at?: string;
          store_id?: string;
          submit_client_mutation_id?: string | null;
          submitted_at?: string | null;
          task_id?: string;
        };
        Relationships: [
          {
            foreignKeyName: "task_attempts_performed_by_fkey";
            columns: ["performed_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_attempts_store_id_fkey";
            columns: ["store_id"];
            isOneToOne: false;
            referencedRelation: "stores";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_attempts_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_attempts_task_store_fkey";
            columns: ["task_id", "store_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["id", "store_id"];
          },
        ];
      };
      task_items: {
        Row: {
          created_at: string;
          id: string;
          is_critical: boolean;
          position: number;
          requires_photo: boolean;
          task_id: string;
          template_item_id: string | null;
          text: string;
          weight: number;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          id?: string;
          is_critical?: boolean;
          position: number;
          requires_photo?: boolean;
          task_id: string;
          template_item_id?: string | null;
          text: string;
          weight?: number;
        };
        Update: {
          created_at?: string;
          id?: string;
          is_critical?: boolean;
          position?: number;
          requires_photo?: boolean;
          task_id?: string;
          template_item_id?: string | null;
          text?: string;
          weight?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_items_task_id_fkey";
            columns: ["task_id"];
            isOneToOne: false;
            referencedRelation: "tasks";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_items_template_item_id_fkey";
            columns: ["template_item_id"];
            isOneToOne: false;
            referencedRelation: "template_items";
            referencedColumns: ["id"];
          },
        ];
      };
      task_templates: {
        Row: {
          created_at: string;
          created_by: string | null;
          default_priority: Database["public"]["Enums"]["task_priority"];
          id: string;
          instructions: string | null;
          is_active: boolean;
          organization_id: string;
          reference_image_path: string | null;
          requires_approval: boolean;
          requires_note: boolean;
          requires_photo: boolean;
          store_id: string | null;
          title: string;
          updated_at: string;
          version: number;
          weight: number;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          created_by?: string | null;
          default_priority?: Database["public"]["Enums"]["task_priority"];
          id?: string;
          instructions?: string | null;
          is_active?: boolean;
          organization_id: string;
          reference_image_path?: string | null;
          requires_approval?: boolean;
          requires_note?: boolean;
          requires_photo?: boolean;
          store_id?: string | null;
          title: string;
          updated_at?: string;
          version?: number;
          weight?: number;
        };
        Update: {
          created_at?: string;
          created_by?: string | null;
          default_priority?: Database["public"]["Enums"]["task_priority"];
          id?: string;
          instructions?: string | null;
          is_active?: boolean;
          organization_id?: string;
          reference_image_path?: string | null;
          requires_approval?: boolean;
          requires_note?: boolean;
          requires_photo?: boolean;
          store_id?: string | null;
          title?: string;
          updated_at?: string;
          version?: number;
          weight?: number;
        };
        Relationships: [
          {
            foreignKeyName: "task_templates_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_templates_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_templates_store_id_fkey";
            columns: ["store_id"];
            isOneToOne: false;
            referencedRelation: "stores";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "task_templates_store_organization_fkey";
            columns: ["store_id", "organization_id"];
            isOneToOne: false;
            referencedRelation: "stores";
            referencedColumns: ["id", "organization_id"];
          },
        ];
      };
      tasks: {
        Row: {
          assignee_at_due: string | null;
          assignee_at_due_recorded: boolean;
          assignee_id: string | null;
          attempt_count: number;
          cancel_reason: string | null;
          cancelled_at: string | null;
          cancelled_by: string | null;
          created_at: string;
          created_by: string | null;
          due_at: string;
          id: string;
          instructions: string | null;
          organization_id: string;
          priority: Database["public"]["Enums"]["task_priority"];
          reference_image_path: string | null;
          requires_approval: boolean;
          requires_note: boolean;
          requires_photo: boolean;
          schedule_id: string | null;
          scheduled_date: string | null;
          sector_id: string;
          status: Database["public"]["Enums"]["task_status"];
          store_id: string;
          template_id: string | null;
          template_version: number | null;
          title: string;
          updated_at: string;
          weight: number;
          window_start_at: string | null;
        };
        ComputedFields: never;
        Insert: {
          assignee_at_due?: string | null;
          assignee_at_due_recorded?: boolean;
          assignee_id?: string | null;
          attempt_count?: number;
          cancel_reason?: string | null;
          cancelled_at?: string | null;
          cancelled_by?: string | null;
          created_at?: string;
          created_by?: string | null;
          due_at: string;
          id?: string;
          instructions?: string | null;
          organization_id: string;
          priority?: Database["public"]["Enums"]["task_priority"];
          reference_image_path?: string | null;
          requires_approval?: boolean;
          requires_note?: boolean;
          requires_photo?: boolean;
          schedule_id?: string | null;
          scheduled_date?: string | null;
          sector_id: string;
          status?: Database["public"]["Enums"]["task_status"];
          store_id: string;
          template_id?: string | null;
          template_version?: number | null;
          title: string;
          updated_at?: string;
          weight?: number;
          window_start_at?: string | null;
        };
        Update: {
          assignee_at_due?: string | null;
          assignee_at_due_recorded?: boolean;
          assignee_id?: string | null;
          attempt_count?: number;
          cancel_reason?: string | null;
          cancelled_at?: string | null;
          cancelled_by?: string | null;
          created_at?: string;
          created_by?: string | null;
          due_at?: string;
          id?: string;
          instructions?: string | null;
          organization_id?: string;
          priority?: Database["public"]["Enums"]["task_priority"];
          reference_image_path?: string | null;
          requires_approval?: boolean;
          requires_note?: boolean;
          requires_photo?: boolean;
          schedule_id?: string | null;
          scheduled_date?: string | null;
          sector_id?: string;
          status?: Database["public"]["Enums"]["task_status"];
          store_id?: string;
          template_id?: string | null;
          template_version?: number | null;
          title?: string;
          updated_at?: string;
          weight?: number;
          window_start_at?: string | null;
        };
        Relationships: [
          {
            foreignKeyName: "tasks_assignee_at_due_fkey";
            columns: ["assignee_at_due"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tasks_assignee_id_fkey";
            columns: ["assignee_id"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tasks_cancelled_by_fkey";
            columns: ["cancelled_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tasks_created_by_fkey";
            columns: ["created_by"];
            isOneToOne: false;
            referencedRelation: "profiles";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tasks_organization_id_fkey";
            columns: ["organization_id"];
            isOneToOne: false;
            referencedRelation: "organizations";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tasks_schedule_id_fkey";
            columns: ["schedule_id"];
            isOneToOne: false;
            referencedRelation: "schedules";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tasks_sector_id_fkey";
            columns: ["sector_id"];
            isOneToOne: false;
            referencedRelation: "sectors";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tasks_sector_store_fkey";
            columns: ["sector_id", "store_id"];
            isOneToOne: false;
            referencedRelation: "sectors";
            referencedColumns: ["id", "store_id"];
          },
          {
            foreignKeyName: "tasks_store_id_fkey";
            columns: ["store_id"];
            isOneToOne: false;
            referencedRelation: "stores";
            referencedColumns: ["id"];
          },
          {
            foreignKeyName: "tasks_store_organization_fkey";
            columns: ["store_id", "organization_id"];
            isOneToOne: false;
            referencedRelation: "stores";
            referencedColumns: ["id", "organization_id"];
          },
          {
            foreignKeyName: "tasks_template_id_fkey";
            columns: ["template_id"];
            isOneToOne: false;
            referencedRelation: "task_templates";
            referencedColumns: ["id"];
          },
        ];
      };
      template_items: {
        Row: {
          created_at: string;
          id: string;
          is_active: boolean;
          is_critical: boolean;
          position: number;
          requires_photo: boolean;
          template_id: string;
          text: string;
          updated_at: string;
          weight: number;
        };
        ComputedFields: never;
        Insert: {
          created_at?: string;
          id?: string;
          is_active?: boolean;
          is_critical?: boolean;
          position: number;
          requires_photo?: boolean;
          template_id: string;
          text: string;
          updated_at?: string;
          weight?: number;
        };
        Update: {
          created_at?: string;
          id?: string;
          is_active?: boolean;
          is_critical?: boolean;
          position?: number;
          requires_photo?: boolean;
          template_id?: string;
          text?: string;
          updated_at?: string;
          weight?: number;
        };
        Relationships: [
          {
            foreignKeyName: "template_items_template_id_fkey";
            columns: ["template_id"];
            isOneToOne: false;
            referencedRelation: "task_templates";
            referencedColumns: ["id"];
          },
        ];
      };
    };
    Views: { [_ in never]: never };
    Functions: {
      admin_read_tasks: {
        Args: { p_from: string; p_store_id: string; p_to: string };
        Returns: {
          assignee_at_due: string | null;
          assignee_at_due_recorded: boolean;
          assignee_id: string | null;
          attempt_count: number;
          cancel_reason: string | null;
          cancelled_at: string | null;
          cancelled_by: string | null;
          created_at: string;
          created_by: string | null;
          due_at: string;
          id: string;
          instructions: string | null;
          organization_id: string;
          priority: Database["public"]["Enums"]["task_priority"];
          reference_image_path: string | null;
          requires_approval: boolean;
          requires_note: boolean;
          requires_photo: boolean;
          schedule_id: string | null;
          scheduled_date: string | null;
          sector_id: string;
          status: Database["public"]["Enums"]["task_status"];
          store_id: string;
          template_id: string | null;
          template_version: number | null;
          title: string;
          updated_at: string;
          weight: number;
          window_start_at: string | null;
        }[];
        SetofOptions: {
          from: "*";
          to: "tasks";
          isOneToOne: false;
          isSetofReturn: true;
        };
      };
      answer_item: {
        Args: { p_attempt_id: string; p_checked: boolean; p_note?: string; p_task_item_id: string };
        Returns: undefined;
      };
      cancel_task: { Args: { p_reason: string; p_task_id: string }; Returns: undefined };
      kpi_summary: {
        Args: {
          p_from: string;
          p_profile_ids?: string[];
          p_sector_ids?: string[];
          p_store_ids?: string[];
          p_to: string;
        };
        Returns: {
          adocao: number;
          aguardando_aprovacao: number;
          aprovadas: number;
          atrasadas: number;
          devolvidas: number;
          executadas: number;
          media_min_atribuicao_envio: number;
          media_min_envio_revisao: number;
          pct_aprovadas_na_janela: number;
          pct_aprovadas_primeira_tentativa: number;
          pendentes: number;
          previstas: number;
        }[];
      };
      log_admin_login: {
        Args: { p_actor_id: string; p_ip?: string; p_user_agent?: string };
        Returns: boolean;
      };
      log_event: { Args: { p_action: string; p_details?: Json }; Returns: undefined };
      register_evidence: {
        Args: {
          p_accuracy_m: number;
          p_attempt_id: string;
          p_captured_at_device: string;
          p_client_mutation_id: string;
          p_exif_present: boolean;
          p_latitude: number;
          p_longitude: number;
          p_phash: number;
          p_sha256: string;
          p_size_bytes: number;
          p_storage_path: string;
          p_task_item_id: string;
        };
        Returns: string;
      };
      review_attempt: {
        Args: {
          p_attempt_id: string;
          p_decision: Database["public"]["Enums"]["review_decision"];
          p_failed_task_item_ids?: string[];
          p_reason?: string;
        };
        Returns: Database["public"]["Enums"]["task_status"];
      };
      set_profile_status: {
        Args: { p_profile_id: string; p_status: Database["public"]["Enums"]["profile_status"] };
        Returns: undefined;
      };
      start_attempt: { Args: { p_client_mutation_id: string; p_task_id: string }; Returns: string };
      submit_attempt: {
        Args: { p_attempt_id: string; p_client_mutation_id?: string; p_note?: string };
        Returns: Database["public"]["Enums"]["task_status"];
      };
      top_failed_items: {
        Args: { p_from: string; p_limit?: number; p_store_ids?: string[]; p_to: string };
        Returns: {
          item_text: string;
          reprovacoes: number;
          store_id: string;
          store_name: string;
          template_item_id: string;
          template_title: string;
        }[];
      };
      weighted_scores: {
        Args: { p_from: string; p_group: string; p_store_ids?: string[]; p_to: string };
        Returns: {
          criticos_reprovados: number;
          group_id: string;
          group_name: string;
          nota: number;
          peso_total: number;
          volume: number;
        }[];
      };
    };
    Enums: {
      action_plan_status: "open" | "in_progress" | "done" | "cancelled";
      data_request_kind: "correction" | "export";
      membership_role: "owner" | "manager" | "staff" | "admin";
      notification_channel: "in_app" | "email";
      notification_type:
        | "due_soon"
        | "overdue"
        | "correction_requested"
        | "recurring_reminder"
        | "awaiting_approval"
        | "escalation_manager"
        | "escalation_owner"
        | "daily_summary"
        | "task_cancelled"
        | "sync_conflict";
      profile_status: "active" | "inactive";
      review_decision: "approved" | "rejected";
      schedule_frequency: "daily" | "weekly" | "monthly" | "specific_days";
      task_priority: "low" | "normal" | "high" | "urgent";
      task_status:
        "pending" | "in_progress" | "submitted" | "approved" | "rejected" | "overdue" | "cancelled";
    };
    CompositeTypes: { [_ in never]: never };
  };
};

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">;

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">];

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R;
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] & DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R;
      }
      ? R
      : never
    : never;

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I;
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I;
      }
      ? I
      : never
    : never;

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    keyof DefaultSchema["Tables"] | { schema: keyof DatabaseWithoutInternals },
  TableName extends (DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never) = never,
> = DefaultSchemaTableNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U;
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U;
      }
      ? U
      : never
    : never;

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    keyof DefaultSchema["Enums"] | { schema: keyof DatabaseWithoutInternals },
  EnumName extends (DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never) = never,
> = DefaultSchemaEnumNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never;

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    keyof DefaultSchema["CompositeTypes"] | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends (PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals;
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never) = never,
> = PublicCompositeTypeNameOrOptions extends { schema: keyof DatabaseWithoutInternals }
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never;

export const Constants = {
  public: {
    Enums: {
      action_plan_status: ["open", "in_progress", "done", "cancelled"],
      data_request_kind: ["correction", "export"],
      membership_role: ["owner", "manager", "staff", "admin"],
      notification_channel: ["in_app", "email"],
      notification_type: [
        "due_soon",
        "overdue",
        "correction_requested",
        "recurring_reminder",
        "awaiting_approval",
        "escalation_manager",
        "escalation_owner",
        "daily_summary",
        "task_cancelled",
        "sync_conflict",
      ],
      profile_status: ["active", "inactive"],
      review_decision: ["approved", "rejected"],
      schedule_frequency: ["daily", "weekly", "monthly", "specific_days"],
      task_priority: ["low", "normal", "high", "urgent"],
      task_status: [
        "pending",
        "in_progress",
        "submitted",
        "approved",
        "rejected",
        "overdue",
        "cancelled",
      ],
    },
  },
} as const;
