import React, { useState } from 'react';
import { Pressable, SafeAreaView, StyleSheet, Text, useWindowDimensions, View } from 'react-native';
import { StatusBar } from 'expo-status-bar';
import Pet from './components/Pet';

const TABS = [
  { key: 'home', label: 'Home', icon: '🏠', blurb: 'Your pet hangs out here.' },
  { key: 'tasks', label: 'Tasks', icon: '✅', blurb: 'One thing at a time.' },
  { key: 'focus', label: 'Focus', icon: '⏱️', blurb: 'Timer goes here.' },
  { key: 'you', label: 'You', icon: '🌱', blurb: 'Streaks and stuff.' },
];

const TAB_BAR_H = 64;

export default function App() {
  const [active, setActive] = useState(0);
  const { width } = useWindowDimensions();
  const tabW = width / TABS.length;
  const tab = TABS[active];

  return (
    <SafeAreaView style={styles.root}>
      <StatusBar style="dark" />
      <View style={styles.page}>
        <Text style={styles.title}>{tab.icon} {tab.label}</Text>
        <Text style={styles.blurb}>{tab.blurb}</Text>
      </View>

      <View style={[styles.tabBar, { height: TAB_BAR_H }]}>
        {TABS.map((t, i) => (
          <Pressable key={t.key} style={styles.tab} onPress={() => setActive(i)}>
            <Text style={styles.tabIcon}>{t.icon}</Text>
            <Text style={[styles.tabLabel, i === active && styles.tabLabelActive]}>{t.label}</Text>
          </Pressable>
        ))}
      </View>

      {/* Pet sits on top of the tab bar and walks to the active tab */}
      <Pet targetX={tabW * active + tabW / 2} bottom={TAB_BAR_H} />
    </SafeAreaView>
  );
}

const styles = StyleSheet.create({
  root: { flex: 1, backgroundColor: '#fff8ef' },
  page: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 8 },
  title: { fontSize: 28, fontWeight: '700', color: '#3b2a3a' },
  blurb: { fontSize: 16, color: '#7a6a7a' },
  tabBar: {
    flexDirection: 'row',
    borderTopWidth: 2,
    borderTopColor: '#3b2a3a',
    backgroundColor: '#ffe9c9',
  },
  tab: { flex: 1, alignItems: 'center', justifyContent: 'center', gap: 2 },
  tabIcon: { fontSize: 20 },
  tabLabel: { fontSize: 12, color: '#7a6a7a' },
  tabLabelActive: { color: '#3b2a3a', fontWeight: '700' },
});
