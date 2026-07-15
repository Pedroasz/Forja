export type Json =
  | string
  | number
  | boolean
  | null
  | { [key: string]: Json | undefined }
  | Json[]

export type Database = {
  public: {
    Tables: {
      account_plan_catalog: {
        Row: {
          account_type: string
          active_client_limit: number | null
          code: string
          created_at: string
          display_name: string
          is_active: boolean
          is_free: boolean
          updated_at: string
        }
        Insert: {
          account_type: string
          active_client_limit?: number | null
          code: string
          created_at?: string
          display_name: string
          is_active?: boolean
          is_free?: boolean
          updated_at?: string
        }
        Update: {
          account_type?: string
          active_client_limit?: number | null
          code?: string
          created_at?: string
          display_name?: string
          is_active?: boolean
          is_free?: boolean
          updated_at?: string
        }
        Relationships: []
      }
      evolution: {
        Row: {
          body_fat: number | null
          chest: number | null
          created_at: string
          hip: number | null
          id: string
          left_arm: number | null
          left_thigh: number | null
          notes: string | null
          record_date: string
          right_arm: number | null
          right_thigh: number | null
          updated_at: string
          user_id: string
          waist: number | null
          weight: number | null
        }
        Insert: {
          body_fat?: number | null
          chest?: number | null
          created_at?: string
          hip?: number | null
          id?: string
          left_arm?: number | null
          left_thigh?: number | null
          notes?: string | null
          record_date: string
          right_arm?: number | null
          right_thigh?: number | null
          updated_at?: string
          user_id: string
          waist?: number | null
          weight?: number | null
        }
        Update: {
          body_fat?: number | null
          chest?: number | null
          created_at?: string
          hip?: number | null
          id?: string
          left_arm?: number | null
          left_thigh?: number | null
          notes?: string | null
          record_date?: string
          right_arm?: number | null
          right_thigh?: number | null
          updated_at?: string
          user_id?: string
          waist?: number | null
          weight?: number | null
        }
        Relationships: []
      }
      hydration: {
        Row: {
          created_at: string
          hydration_date: string
          id: string
          total_ml: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          hydration_date: string
          id?: string
          total_ml?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          hydration_date?: string
          id?: string
          total_ml?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      meals: {
        Row: {
          created_at: string
          id: string
          items: Json
          meal_date: string
          total_calories: number
          total_carbs: number
          total_fat: number
          total_protein: number
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          items?: Json
          meal_date: string
          total_calories?: number
          total_carbs?: number
          total_fat?: number
          total_protein?: number
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          items?: Json
          meal_date?: string
          total_calories?: number
          total_carbs?: number
          total_fat?: number
          total_protein?: number
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      organization_members: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          joined_at: string | null
          organization_id: string
          role: string
          status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          joined_at?: string | null
          organization_id: string
          role: string
          status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          joined_at?: string | null
          organization_id?: string
          role?: string
          status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "organization_members_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      organizations: {
        Row: {
          created_at: string
          id: string
          name: string
          organization_type: string
          owner_user_id: string
          slug: string
          status: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          id?: string
          name: string
          organization_type: string
          owner_user_id: string
          slug: string
          status?: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          id?: string
          name?: string
          organization_type?: string
          owner_user_id?: string
          slug?: string
          status?: string
          updated_at?: string
        }
        Relationships: []
      }
      platform_user_roles: {
        Row: {
          created_at: string
          created_by: string | null
          id: string
          role: string
          user_id: string
        }
        Insert: {
          created_at?: string
          created_by?: string | null
          id?: string
          role: string
          user_id: string
        }
        Update: {
          created_at?: string
          created_by?: string | null
          id?: string
          role?: string
          user_id?: string
        }
        Relationships: []
      }
      professional_nutrition_templates: {
        Row: {
          created_at: string
          description: string | null
          id: string
          organization_id: string | null
          owner_user_id: string
          plan_data: Json
          schema_version: number
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          organization_id?: string | null
          owner_user_id: string
          plan_data: Json
          schema_version?: number
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          organization_id?: string | null
          owner_user_id?: string
          plan_data?: Json
          schema_version?: number
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "professional_nutrition_templates_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      professional_student_relationships: {
        Row: {
          accepted_at: string | null
          created_at: string
          id: string
          organization_id: string | null
          professional_type: string
          professional_user_id: string
          requested_by: string | null
          revoked_at: string | null
          scopes: Json
          status: string
          student_user_id: string
          updated_at: string
        }
        Insert: {
          accepted_at?: string | null
          created_at?: string
          id?: string
          organization_id?: string | null
          professional_type: string
          professional_user_id: string
          requested_by?: string | null
          revoked_at?: string | null
          scopes?: Json
          status?: string
          student_user_id: string
          updated_at?: string
        }
        Update: {
          accepted_at?: string | null
          created_at?: string
          id?: string
          organization_id?: string | null
          professional_type?: string
          professional_user_id?: string
          requested_by?: string | null
          revoked_at?: string | null
          scopes?: Json
          status?: string
          student_user_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "professional_student_relationships_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      professional_workout_templates: {
        Row: {
          created_at: string
          description: string | null
          id: string
          organization_id: string | null
          owner_user_id: string
          plan_data: Json
          schema_version: number
          status: string
          title: string
          updated_at: string
        }
        Insert: {
          created_at?: string
          description?: string | null
          id?: string
          organization_id?: string | null
          owner_user_id: string
          plan_data: Json
          schema_version?: number
          status?: string
          title: string
          updated_at?: string
        }
        Update: {
          created_at?: string
          description?: string | null
          id?: string
          organization_id?: string | null
          owner_user_id?: string
          plan_data?: Json
          schema_version?: number
          status?: string
          title?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "professional_workout_templates_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      profiles: {
        Row: {
          birth_date: string | null
          created_at: string
          display_name: string | null
          email: string | null
          full_name: string | null
          gender: string | null
          goal: string | null
          height: number | null
          id: string
          locale: string | null
          name: string | null
          onboarding_completed: boolean
          onboarding_step: number
          phone: string | null
          theme: string | null
          timezone: string | null
          updated_at: string
          user_id: string
          weight_goal: number | null
        }
        Insert: {
          birth_date?: string | null
          created_at?: string
          display_name?: string | null
          email?: string | null
          full_name?: string | null
          gender?: string | null
          goal?: string | null
          height?: number | null
          id?: string
          locale?: string | null
          name?: string | null
          onboarding_completed?: boolean
          onboarding_step?: number
          phone?: string | null
          theme?: string | null
          timezone?: string | null
          updated_at?: string
          user_id: string
          weight_goal?: number | null
        }
        Update: {
          birth_date?: string | null
          created_at?: string
          display_name?: string | null
          email?: string | null
          full_name?: string | null
          gender?: string | null
          goal?: string | null
          height?: number | null
          id?: string
          locale?: string | null
          name?: string | null
          onboarding_completed?: boolean
          onboarding_step?: number
          phone?: string | null
          theme?: string | null
          timezone?: string | null
          updated_at?: string
          user_id?: string
          weight_goal?: number | null
        }
        Relationships: []
      }
      student_nutrition_assignments: {
        Row: {
          assigned_at: string
          assignment_version: number
          created_at: string
          description_snapshot: string | null
          effective_from: string | null
          effective_until: string | null
          id: string
          plan_data_snapshot: Json
          relationship_id: string
          revoked_at: string | null
          schema_version: number
          status: string
          superseded_at: string | null
          template_id: string | null
          title_snapshot: string
          updated_at: string
        }
        Insert: {
          assigned_at?: string
          assignment_version: number
          created_at?: string
          description_snapshot?: string | null
          effective_from?: string | null
          effective_until?: string | null
          id?: string
          plan_data_snapshot: Json
          relationship_id: string
          revoked_at?: string | null
          schema_version?: number
          status?: string
          superseded_at?: string | null
          template_id?: string | null
          title_snapshot: string
          updated_at?: string
        }
        Update: {
          assigned_at?: string
          assignment_version?: number
          created_at?: string
          description_snapshot?: string | null
          effective_from?: string | null
          effective_until?: string | null
          id?: string
          plan_data_snapshot?: Json
          relationship_id?: string
          revoked_at?: string | null
          schema_version?: number
          status?: string
          superseded_at?: string | null
          template_id?: string | null
          title_snapshot?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "student_nutrition_assignments_relationship_id_fkey"
            columns: ["relationship_id"]
            isOneToOne: false
            referencedRelation: "professional_student_relationships"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "student_nutrition_assignments_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "professional_nutrition_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      student_workout_assignments: {
        Row: {
          assigned_at: string
          assignment_version: number
          created_at: string
          description_snapshot: string | null
          effective_from: string | null
          id: string
          plan_data_snapshot: Json
          relationship_id: string
          revoked_at: string | null
          schema_version: number
          status: string
          superseded_at: string | null
          template_id: string | null
          title_snapshot: string
          updated_at: string
        }
        Insert: {
          assigned_at?: string
          assignment_version: number
          created_at?: string
          description_snapshot?: string | null
          effective_from?: string | null
          id?: string
          plan_data_snapshot: Json
          relationship_id: string
          revoked_at?: string | null
          schema_version?: number
          status?: string
          superseded_at?: string | null
          template_id?: string | null
          title_snapshot: string
          updated_at?: string
        }
        Update: {
          assigned_at?: string
          assignment_version?: number
          created_at?: string
          description_snapshot?: string | null
          effective_from?: string | null
          id?: string
          plan_data_snapshot?: Json
          relationship_id?: string
          revoked_at?: string | null
          schema_version?: number
          status?: string
          superseded_at?: string | null
          template_id?: string | null
          title_snapshot?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "student_workout_assignments_relationship_id_fkey"
            columns: ["relationship_id"]
            isOneToOne: false
            referencedRelation: "professional_student_relationships"
            referencedColumns: ["id"]
          },
          {
            foreignKeyName: "student_workout_assignments_template_id_fkey"
            columns: ["template_id"]
            isOneToOne: false
            referencedRelation: "professional_workout_templates"
            referencedColumns: ["id"]
          },
        ]
      }
      trainer_student_invitations: {
        Row: {
          accepted_at: string | null
          accepted_by_user_id: string | null
          cancelled_at: string | null
          created_at: string
          expires_at: string
          id: string
          invite_code_hash: string
          invite_code_prefix: string
          status: string
          trainer_user_id: string
          updated_at: string
        }
        Insert: {
          accepted_at?: string | null
          accepted_by_user_id?: string | null
          cancelled_at?: string | null
          created_at?: string
          expires_at: string
          id?: string
          invite_code_hash: string
          invite_code_prefix: string
          status?: string
          trainer_user_id: string
          updated_at?: string
        }
        Update: {
          accepted_at?: string | null
          accepted_by_user_id?: string | null
          cancelled_at?: string | null
          created_at?: string
          expires_at?: string
          id?: string
          invite_code_hash?: string
          invite_code_prefix?: string
          status?: string
          trainer_user_id?: string
          updated_at?: string
        }
        Relationships: []
      }
      trainer_student_relationships: {
        Row: {
          accepted_at: string | null
          created_at: string
          id: string
          organization_id: string | null
          permissions: Json
          requested_by: string | null
          revoked_at: string | null
          status: string
          student_user_id: string
          trainer_user_id: string
          updated_at: string
        }
        Insert: {
          accepted_at?: string | null
          created_at?: string
          id?: string
          organization_id?: string | null
          permissions?: Json
          requested_by?: string | null
          revoked_at?: string | null
          status?: string
          student_user_id: string
          trainer_user_id: string
          updated_at?: string
        }
        Update: {
          accepted_at?: string | null
          created_at?: string
          id?: string
          organization_id?: string | null
          permissions?: Json
          requested_by?: string | null
          revoked_at?: string | null
          status?: string
          student_user_id?: string
          trainer_user_id?: string
          updated_at?: string
        }
        Relationships: [
          {
            foreignKeyName: "trainer_student_relationships_organization_id_fkey"
            columns: ["organization_id"]
            isOneToOne: false
            referencedRelation: "organizations"
            referencedColumns: ["id"]
          },
        ]
      }
      user_account_modes: {
        Row: {
          created_at: string
          id: string
          mode: string
          updated_at: string
          user_id: string
        }
        Insert: {
          created_at?: string
          id?: string
          mode: string
          updated_at?: string
          user_id: string
        }
        Update: {
          created_at?: string
          id?: string
          mode?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_commercial_accounts: {
        Row: {
          account_type_selected_at: string | null
          created_at: string
          personal_use_enabled: boolean
          plan_code: string | null
          primary_account_type: string | null
          subscription_status: string
          updated_at: string
          user_id: string
        }
        Insert: {
          account_type_selected_at?: string | null
          created_at?: string
          personal_use_enabled?: boolean
          plan_code?: string | null
          primary_account_type?: string | null
          subscription_status?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          account_type_selected_at?: string | null
          created_at?: string
          personal_use_enabled?: boolean
          plan_code?: string | null
          primary_account_type?: string | null
          subscription_status?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: [
          {
            foreignKeyName: "user_commercial_accounts_plan_type_fk"
            columns: ["plan_code", "primary_account_type"]
            isOneToOne: false
            referencedRelation: "account_plan_catalog"
            referencedColumns: ["code", "account_type"]
          },
        ]
      }
      user_identity_details: {
        Row: {
          age_status: string
          age_verified_at: string | null
          birth_date: string
          country_code: string
          created_at: string
          updated_at: string
          user_id: string
        }
        Insert: {
          age_status: string
          age_verified_at?: string | null
          birth_date: string
          country_code?: string
          created_at?: string
          updated_at?: string
          user_id: string
        }
        Update: {
          age_status?: string
          age_verified_at?: string | null
          birth_date?: string
          country_code?: string
          created_at?: string
          updated_at?: string
          user_id?: string
        }
        Relationships: []
      }
      user_legal_acceptances: {
        Row: {
          accepted_at: string
          created_at: string
          document_type: string
          document_version: string
          id: string
          user_id: string
        }
        Insert: {
          accepted_at?: string
          created_at?: string
          document_type: string
          document_version: string
          id?: string
          user_id: string
        }
        Update: {
          accepted_at?: string
          created_at?: string
          document_type?: string
          document_version?: string
          id?: string
          user_id?: string
        }
        Relationships: []
      }
      user_notifications: {
        Row: {
          actor_user_id: string | null
          created_at: string
          dedupe_key: string | null
          entity_id: string | null
          entity_type: string | null
          expires_at: string | null
          id: string
          message: string
          metadata: Json
          notification_type: string
          read_at: string | null
          recipient_user_id: string
          title: string
        }
        Insert: {
          actor_user_id?: string | null
          created_at?: string
          dedupe_key?: string | null
          entity_id?: string | null
          entity_type?: string | null
          expires_at?: string | null
          id?: string
          message: string
          metadata?: Json
          notification_type: string
          read_at?: string | null
          recipient_user_id: string
          title: string
        }
        Update: {
          actor_user_id?: string | null
          created_at?: string
          dedupe_key?: string | null
          entity_id?: string | null
          entity_type?: string | null
          expires_at?: string | null
          id?: string
          message?: string
          metadata?: Json
          notification_type?: string
          read_at?: string | null
          recipient_user_id?: string
          title?: string
        }
        Relationships: []
      }
      workouts: {
        Row: {
          created_at: string
          duration_minutes: number | null
          exercises: Json
          id: string
          name: string | null
          total_volume: number
          updated_at: string
          user_id: string
          workout_date: string
        }
        Insert: {
          created_at?: string
          duration_minutes?: number | null
          exercises?: Json
          id?: string
          name?: string | null
          total_volume?: number
          updated_at?: string
          user_id: string
          workout_date: string
        }
        Update: {
          created_at?: string
          duration_minutes?: number | null
          exercises?: Json
          id?: string
          name?: string | null
          total_volume?: number
          updated_at?: string
          user_id?: string
          workout_date?: string
        }
        Relationships: []
      }
    }
    Views: {
      [_ in never]: never
    }
    Functions: {
      accept_trainer_student_invitation: {
        Args: { invite_code: string }
        Returns: Json
      }
      archive_my_nutrition_template: {
        Args: { target_template_id: string }
        Returns: Json
      }
      archive_my_workout_template: {
        Args: { target_template_id: string }
        Returns: Json
      }
      assert_my_nutritionist_identity_v41c: { Args: never; Returns: undefined }
      assert_my_nutritionist_write_access_v41c: {
        Args: never
        Returns: undefined
      }
      assert_my_trainer_identity_v41b: { Args: never; Returns: undefined }
      assert_my_trainer_write_access_v41b: { Args: never; Returns: undefined }
      assert_professional_client_capacity_v41a2: {
        Args: {
          relationship_id_to_exclude?: string
          target_professional_id: string
          target_professional_type: string
          target_student_id: string
        }
        Returns: undefined
      }
      assert_professional_monitoring_page_v41d: {
        Args: {
          target_cursor_date: string
          target_cursor_id: string
          target_end_date: string
          target_limit: number
          target_start_date: string
        }
        Returns: undefined
      }
      assign_nutrition_template_to_student: {
        Args: {
          target_effective_from?: string
          target_effective_until?: string
          target_relationship_id: string
          target_template_id: string
        }
        Returns: Json
      }
      assign_workout_template_to_student: {
        Args: {
          target_effective_from?: string
          target_relationship_id: string
          target_template_id: string
        }
        Returns: Json
      }
      cancel_trainer_invitation: {
        Args: { invitation_id: string }
        Returns: boolean
      }
      complete_my_initial_account_setup: {
        Args: {
          accepted_privacy_version: string
          accepted_terms_version: string
          target_account_type: string
          target_birth_date: string
          target_display_name: string
          target_full_name: string
        }
        Returns: Json
      }
      create_my_nutrition_template: {
        Args: {
          target_description: string
          target_organization_id?: string
          target_plan_data: Json
          target_title: string
        }
        Returns: Json
      }
      create_my_workout_template: {
        Args: {
          target_description: string
          target_organization_id?: string
          target_plan_data: Json
          target_title: string
        }
        Returns: Json
      }
      create_trainer_student_invitation: { Args: never; Returns: Json }
      create_user_notification_v41c: {
        Args: {
          target_actor_user_id: string
          target_dedupe_key: string
          target_entity_id: string
          target_entity_type: string
          target_message: string
          target_metadata?: Json
          target_notification_type: string
          target_recipient_user_id: string
          target_title: string
        }
        Returns: string
      }
      default_professional_relationship_scopes_v41e1: {
        Args: { target_professional_type: string }
        Returns: Json
      }
      default_professional_scopes: {
        Args: { target_professional_type: string }
        Returns: Json
      }
      get_current_access_context: { Args: never; Returns: Json }
      get_current_access_context_v41a: { Args: never; Returns: Json }
      get_my_account_modes: { Args: never; Returns: string[] }
      get_my_account_registration_context: { Args: never; Returns: Json }
      get_my_commercial_account_context: { Args: never; Returns: Json }
      get_my_professional_client_capacity: { Args: never; Returns: Json }
      get_my_professional_monitoring_entitlement_v41d: {
        Args: {
          target_allowed_professional_types: string[]
          target_relationship_id: string
          target_required_scope: string
        }
        Returns: string
      }
      get_my_unread_notification_count: { Args: never; Returns: number }
      get_professional_active_client_count_v41a2: {
        Args: {
          relationship_id_to_exclude?: string
          target_professional_id: string
          target_professional_type: string
        }
        Returns: number
      }
      has_active_professional_relationship: {
        Args: {
          professional_id: string
          required_scope?: string
          student_id: string
          target_organization_id?: string
          target_professional_type: string
        }
        Returns: boolean
      }
      has_active_trainer_student_relationship: {
        Args: {
          required_permission?: string
          target_student_id: string
          target_trainer_id: string
        }
        Returns: boolean
      }
      has_organization_role: {
        Args: {
          allowed_roles: string[]
          target_organization_id: string
          target_user_id?: string
        }
        Returns: boolean
      }
      is_organization_member: {
        Args: { target_organization_id: string; target_user_id?: string }
        Returns: boolean
      }
      list_my_assigned_nutrition_plans: {
        Args: { target_local_date: string }
        Returns: Json
      }
      list_my_assigned_workout_plans: { Args: never; Returns: Json }
      list_my_manageable_nutrition_students: { Args: never; Returns: Json }
      list_my_manageable_workout_students: { Args: never; Returns: Json }
      list_my_notifications: {
        Args: { target_before?: string; target_limit?: number }
        Returns: Json
      }
      list_my_nutrition_templates: { Args: never; Returns: Json }
      list_my_student_evolution: {
        Args: {
          target_cursor_date?: string
          target_cursor_id?: string
          target_end_date: string
          target_limit: number
          target_relationship_id: string
          target_start_date: string
        }
        Returns: Json
      }
      list_my_student_nutrition_logs: {
        Args: {
          target_cursor_date?: string
          target_cursor_id?: string
          target_end_date: string
          target_limit: number
          target_relationship_id: string
          target_start_date: string
        }
        Returns: Json
      }
      list_my_student_workout_executions: {
        Args: {
          target_cursor_date?: string
          target_cursor_id?: string
          target_end_date: string
          target_limit: number
          target_relationship_id: string
          target_start_date: string
        }
        Returns: Json
      }
      list_my_trainer_invitations: {
        Args: never
        Returns: {
          accepted_at: string
          cancelled_at: string
          created_at: string
          expires_at: string
          id: string
          invite_code_prefix: string
          status: string
        }[]
      }
      list_my_trainer_student_connections: {
        Args: never
        Returns: {
          display_name: string
          permissions: Json
          relationship_id: string
          role_in_relationship: string
          status: string
        }[]
      }
      list_my_workout_templates: { Args: never; Returns: Json }
      mark_all_my_notifications_read: { Args: never; Returns: number }
      mark_my_notification_read: {
        Args: { target_notification_id: string }
        Returns: Json
      }
      normalize_invitation_code: {
        Args: { input_code: string }
        Returns: string
      }
      notification_iso_date_is_valid_v41c: {
        Args: { target_value: string }
        Returns: boolean
      }
      notification_metadata_is_safe_v41c: {
        Args: { target_value: Json }
        Returns: boolean
      }
      nutrition_text_is_safe_v41c: {
        Args: { target_max_length: number; target_value: string }
        Returns: boolean
      }
      nutrition_unit_is_supported_v41c: {
        Args: { target_unit: string }
        Returns: boolean
      }
      preview_trainer_invitation: {
        Args: { invite_code: string }
        Returns: Json
      }
      revoke_my_student_nutrition_assignment: {
        Args: { target_assignment_id: string }
        Returns: Json
      }
      revoke_my_student_workout_assignment: {
        Args: { target_assignment_id: string }
        Returns: Json
      }
      set_my_account_modes: {
        Args: { requested_modes: string[] }
        Returns: string[]
      }
      set_my_personal_use_enabled: {
        Args: { target_enabled: boolean }
        Returns: Json
      }
      update_my_nutrition_template: {
        Args: {
          target_description: string
          target_plan_data: Json
          target_template_id: string
          target_title: string
        }
        Returns: Json
      }
      update_my_workout_template: {
        Args: {
          target_description: string
          target_plan_data: Json
          target_template_id: string
          target_title: string
        }
        Returns: Json
      }
      validate_nutrition_plan_payload_v41c: {
        Args: { plan_data: Json }
        Returns: boolean
      }
      validate_workout_plan_payload_v41b: {
        Args: { plan_data: Json }
        Returns: boolean
      }
    }
    Enums: {
      [_ in never]: never
    }
    CompositeTypes: {
      [_ in never]: never
    }
  }
}

type DatabaseWithoutInternals = Omit<Database, "__InternalSupabase">

type DefaultSchema = DatabaseWithoutInternals[Extract<keyof Database, "public">]

export type Tables<
  DefaultSchemaTableNameOrOptions extends
    | keyof (DefaultSchema["Tables"] & DefaultSchema["Views"])
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
        DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? (DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"] &
      DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Views"])[TableName] extends {
      Row: infer R
    }
    ? R
    : never
  : DefaultSchemaTableNameOrOptions extends keyof (DefaultSchema["Tables"] &
        DefaultSchema["Views"])
    ? (DefaultSchema["Tables"] &
        DefaultSchema["Views"])[DefaultSchemaTableNameOrOptions] extends {
        Row: infer R
      }
      ? R
      : never
    : never

export type TablesInsert<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Insert: infer I
    }
    ? I
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Insert: infer I
      }
      ? I
      : never
    : never

export type TablesUpdate<
  DefaultSchemaTableNameOrOptions extends
    | keyof DefaultSchema["Tables"]
    | { schema: keyof DatabaseWithoutInternals },
  TableName extends DefaultSchemaTableNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"]
    : never = never,
> = DefaultSchemaTableNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaTableNameOrOptions["schema"]]["Tables"][TableName] extends {
      Update: infer U
    }
    ? U
    : never
  : DefaultSchemaTableNameOrOptions extends keyof DefaultSchema["Tables"]
    ? DefaultSchema["Tables"][DefaultSchemaTableNameOrOptions] extends {
        Update: infer U
      }
      ? U
      : never
    : never

export type Enums<
  DefaultSchemaEnumNameOrOptions extends
    | keyof DefaultSchema["Enums"]
    | { schema: keyof DatabaseWithoutInternals },
  EnumName extends DefaultSchemaEnumNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"]
    : never = never,
> = DefaultSchemaEnumNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[DefaultSchemaEnumNameOrOptions["schema"]]["Enums"][EnumName]
  : DefaultSchemaEnumNameOrOptions extends keyof DefaultSchema["Enums"]
    ? DefaultSchema["Enums"][DefaultSchemaEnumNameOrOptions]
    : never

export type CompositeTypes<
  PublicCompositeTypeNameOrOptions extends
    | keyof DefaultSchema["CompositeTypes"]
    | { schema: keyof DatabaseWithoutInternals },
  CompositeTypeName extends PublicCompositeTypeNameOrOptions extends {
    schema: keyof DatabaseWithoutInternals
  }
    ? keyof DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"]
    : never = never,
> = PublicCompositeTypeNameOrOptions extends {
  schema: keyof DatabaseWithoutInternals
}
  ? DatabaseWithoutInternals[PublicCompositeTypeNameOrOptions["schema"]]["CompositeTypes"][CompositeTypeName]
  : PublicCompositeTypeNameOrOptions extends keyof DefaultSchema["CompositeTypes"]
    ? DefaultSchema["CompositeTypes"][PublicCompositeTypeNameOrOptions]
    : never

export const Constants = {
  public: {
    Enums: {},
  },
} as const
