import { useEffect, useState } from "react";
import './App.css'
import { supabase } from '../supabaseClient';
import { ThemeSupa } from '@supabase/auth-ui-shared'

function App() {
  const [session, setSession] = useState(null);
  
  useEffect(() => {
    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session);
    });

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session);
    });

    return () => subscription.unsubscribe();
  }, []);

  if(!session) {
    return <Auth supbaseClient={supabase} appearance={{ theme: ThemeSupa }} />
  } else {
    return <div>Logged in!</div>
  }
}

export default App
