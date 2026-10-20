import '../game/dice.dart';

const _first = {
  'human': ['Aldric', 'Mara', 'Corwin', 'Elena', 'Tobias', 'Isolde', 'Garrett', 'Rowan', 'Selene', 'Bram', 'Wren', 'Cassian', 'Livia', 'Dorian', 'Hesper'],
  'elf': ['Aelar', 'Ilyndra', 'Thalion', 'Sylvaris', 'Naivara', 'Erevan', 'Lia', 'Caelynn', 'Faelar', 'Quelenna', 'Soveliss', 'Thamior', 'Vaeril', 'Aerin'],
  'dwarf': ['Brannoc', 'Helga', 'Thorin', 'Dagna', 'Ulfgar', 'Vistra', 'Grimli', 'Eldeth', 'Rurik', 'Torbera', 'Baern', 'Kathra'],
  'halfling': ['Pip', 'Lyra', 'Milo', 'Rosie', 'Cade', 'Merry', 'Finnan', 'Seraphina', 'Wellby', 'Callie', 'Roscoe', 'Tansy'],
  'gnome': ['Fizzwick', 'Nissa', 'Boddynock', 'Carlin', 'Bimpnottin', 'Orryn', 'Zook', 'Ellyjobell', 'Wrenn', 'Roondar'],
  'half-elf': ['Kaelen', 'Tessaly', 'Riven', 'Aurelie', 'Joren', 'Evanthe', 'Lucan', 'Miriel', 'Soren', 'Yelena'],
  'half-orc': ['Grom', 'Shura', 'Dench', 'Baggi', 'Krusk', 'Volen', 'Holg', 'Yevelda', 'Thokk', 'Ovak'],
  'tiefling': ['Thalos', 'Nyx', 'Mordai', 'Lerissa', 'Kallista', 'Akmenos', 'Orianna', 'Damakos', 'Rieta', 'Ekemon', 'Zariel'],
  'dragonborn': ['Arjhan', 'Sora', 'Kriv', 'Biri', 'Medrash', 'Daar', 'Nadarr', 'Harann', 'Torinn', 'Kava'],
};

const _last = {
  'human': ['Ravenmoor', 'Ashford', 'Blackwood', 'Vance', 'Thornfield', 'Greaves', 'Holloway', 'Marsh', 'Sterling', 'Duskmantle'],
  'elf': ['Starwhisper', 'Moonbrook', 'Amakiir', 'Galanodel', 'Siannodel', 'Liadon', 'Nailo', 'Silverfrond'],
  'dwarf': ['Ironvein', 'Stonehelm', 'Battlehammer', 'Fireforge', 'Gorunn', 'Rumnaheim', 'Deepdelver'],
  'halfling': ['Thistledown', 'Goodbarrel', 'Tealeaf', 'Brushgather', 'Underbough', 'Highhill'],
  'gnome': ['Quillfeather', 'Cogsworth', 'Nackle', 'Turen', 'Fiddlelock', 'Timbers'],
  'half-elf': ['Duskmantle', 'Vale', 'Oakensong', 'Brightwater', 'Silvan', 'Wyndham'],
  'half-orc': ['Bloodtusk', 'Skullsplitter', 'Ironjaw', 'Ashbrand', 'Gorefang'],
  'tiefling': ['Emberveil', 'Ashgrave', 'Nightbloom', 'Cinder', 'Hollowheart', 'Vex'],
  'dragonborn': ['Kerrhylon', 'Myastan', 'Daardendrian', 'Yarjerit', 'Clethtinthiallor'],
};

const _epithets = [
  'Blade of Frontiers', 'the Unbroken', 'Ember of the Waste', 'Whisper in the Dark', 'Warden of the Old Road', 'Scion of Storms',
  'the Lantern-Bearer', 'Thorn of the Vale', 'Breaker of Oaths', 'Child of the Moon', 'the Ashen Saint', 'Keeper of Small Fires',
  'the Wandering Star', 'Voice of the Deep', 'Hound of the Crown', 'the Last Ember',
];

String randomName(String raceId, {Rng? rng}) {
  final r = rng ?? Rng.unseeded();
  final f = _first[raceId] ?? _first['human']!;
  final l = _last[raceId] ?? _last['human']!;
  return '${r.pick(f)} ${r.pick(l)}';
}

String randomEpithet({Rng? rng}) => (rng ?? Rng.unseeded()).pick(_epithets);

const _npcFirst = ['Old Hesk', 'Marta', 'Brother Aldo', 'Captain Ysolde', 'Fenwick', 'Grizelda', 'Tam', 'Lady Voss', 'Orrin', 'Mother Nettle', 'Jory', 'Sable', 'Quill', 'Haddie', 'Vorn', 'Ilse', 'Pell', 'Magister Crane', 'Rook', 'Ansel'];
const _npcRoles = ['innkeeper', 'blacksmith', 'priest', 'guard captain', 'merchant', 'hermit', 'farmer', 'noble', 'scholar', 'thief', 'witch', 'bard', 'hunter', 'ferryman', 'apothecary'];

String randomNpcName({Rng? rng}) => (rng ?? Rng.unseeded()).pick(_npcFirst);
String randomNpcRole({Rng? rng}) => (rng ?? Rng.unseeded()).pick(_npcRoles);

const _placePre = ['Raven', 'Thorn', 'Ash', 'Grim', 'Silver', 'Black', 'Wyrm', 'Hollow', 'Mist', 'Frost', 'Ember', 'Gloom', 'Stone', 'Elder', 'Briar', 'Dusk'];
const _placeSuf = ['hollow', 'reach', 'vale', 'mere', 'ford', 'crag', 'keep', 'wood', 'barrow', 'march', 'deep', 'fell', 'watch', 'spire', 'moor'];

String randomPlace({Rng? rng}) {
  final r = rng ?? Rng.unseeded();
  return '${r.pick(_placePre)}${r.pick(_placeSuf)}';
}
